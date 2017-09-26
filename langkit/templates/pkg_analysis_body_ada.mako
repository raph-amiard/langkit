## vim: filetype=makoada

<%namespace name="array_types"       file="array_types_ada.mako" />
<%namespace name="astnode_types"     file="astnode_types_ada.mako" />
<%namespace name="enum_types"        file="enum_types_ada.mako" />
<%namespace name="list_types"        file="list_types_ada.mako" />
<%namespace name="struct_types"      file="struct_types_ada.mako" />
<%namespace name="public_properties" file="public_properties_ada.mako" />

<% root_node_array = T.root_node.array %>

with Ada.Containers;                  use Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Ordered_Maps;
with Ada.Exceptions;
with Ada.Strings.Wide_Wide_Unbounded; use Ada.Strings.Wide_Wide_Unbounded;
with Ada.Text_IO;                     use Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

with System.Address_Image;
with System.Storage_Elements;    use System.Storage_Elements;

with Langkit_Support.Array_Utils;
with Langkit_Support.Images;  use Langkit_Support.Images;
with Langkit_Support.Relative_Get;
with Langkit_Support.Slocs;   use Langkit_Support.Slocs;
with Langkit_Support.Text;    use Langkit_Support.Text;

pragma Warnings (Off, "referenced");
with Langkit_Support.Adalog.Abstract_Relation;
use Langkit_Support.Adalog.Abstract_Relation;
with Langkit_Support.Adalog.Debug;
use Langkit_Support.Adalog.Debug;
with Langkit_Support.Adalog.Operations;
use Langkit_Support.Adalog.Operations;
with Langkit_Support.Adalog.Predicates;
use Langkit_Support.Adalog.Predicates;
with Langkit_Support.Adalog.Pure_Relations;
use Langkit_Support.Adalog.Pure_Relations;
pragma Warnings (On, "referenced");

with ${ada_lib_name}.Analysis.Parsers; use ${ada_lib_name}.Analysis.Parsers;
with ${ada_lib_name}.Lexer;

%if ctx.env_hook_subprogram:
with ${ctx.env_hook_subprogram.unit_fqn};
%endif
%if ctx.default_unit_provider:
with ${ctx.default_unit_provider.unit_fqn};
%endif
%if ctx.symbol_canonicalizer:
with ${ctx.symbol_canonicalizer.unit_fqn};
%endif

package body ${ada_lib_name}.Analysis is

   type Analysis_Context_Private_Part_Type is record
      Parser : Parser_Type;
      --  Main parser type. TODO: If we want to parse in several tasks, we'll
      --  replace that by an array of parsers.
   end record;

   ${array_types.body(root_node_array)}

   % for array_type in ctx.sorted_types(ctx.array_types):
   % if array_type.element_type.should_emit_array_type:
   ${array_types.body(array_type)}
   % endif
   % endfor

   procedure Destroy (Self : in out Lex_Env_Data_Type);
   --  Destroy data associated to lexical environments

   type Containing_Env_Element is record
      Env  : Lexical_Env;
      Key  : Symbol_Type;
      Node : ${root_node_type_name};
   end record;
   --  Tuple of values passed to Lexical_Env.Add. Used in the lexical
   --  environment rerooting machinery: see Lex_Env_Data_Type.

   package Containing_Envs is new Langkit_Support.Vectors
     (Containing_Env_Element);

   type Lex_Env_Data_Type is record
      Is_Contained_By : Containing_Envs.Vector;
      --  Lexical env population for the unit that owns this Lex_Env_Data may
      --  have added AST nodes it owns to the lexical environments that belong
      --  to other units. For each of these AST nodes, this vector contains an
      --  entry that records the target environment, the AST node and the
      --  corresponding symbol.

      Contains : ${root_node_type_name}_Vectors.Vector;
      --  The unit that owns this Lex_Env_Data owns a set of lexical
      --  environments. This vector contains the list of AST nodes that were
      --  added to these environments and that come from other units.
   end record;

   procedure Remove_Exiled_Entries (Self : Lex_Env_Data);
   --  Remove lex env entries that references some of the unit's nodes, in
   --  lexical environments not owned by the unit.

   procedure Reroot_Foreign_Nodes
     (Self : Lex_Env_Data; Root_Scope : Lexical_Env);
   --  Re-create entries for nodes that are keyed in one of the unit's lexical
   --  envs.

   procedure Update_After_Reparse (Unit : Analysis_Unit);
   --  Update stale lexical environment data after the reparsing of Unit

   ## Utility package
   package ${root_node_type_name}_Arrays
   is new Langkit_Support.Array_Utils
     (${root_node_type_name},
      ${root_node_array.pkg_vector}.Index_Type,
      ${root_node_array.pkg_vector}.Elements_Array);

   ##  Make logic operations on nodes accessible
   use Eq_Node, Eq_Node.Raw_Impl;

   procedure Destroy (Unit : Analysis_Unit);

   procedure Free is new Ada.Unchecked_Deallocation
     (Analysis_Context_Type, Analysis_Context);

   procedure Free is new Ada.Unchecked_Deallocation
     (Analysis_Unit_Type, Analysis_Unit);

   procedure Update_Charset (Unit : Analysis_Unit; Charset : String);
   --  If Charset is an empty string, do nothing. Otherwise, update
   --  Unit.Charset field to Charset.

   procedure Do_Parsing
     (Unit        : Analysis_Unit;
      Read_BOM    : Boolean;
      Init_Parser : access procedure (Unit     : Analysis_Unit;
                                      Read_BOM : Boolean;
                                      Parser   : in out Parser_Type));
   --  Helper for Get_Unit and the public Reparse procedures: parse an analysis
   --  unit using Init_Parser and replace Unit's AST_Root and the diagnostics
   --  with the parsers's output.

   function Create_Unit
     (Context           : Analysis_Context;
      Filename, Charset : String;
      With_Trivia       : Boolean;
      Rule              : Grammar_Rule) return Analysis_Unit
      with Pre => not Has_Unit (Context, Filename);
   --  Create a new analysis unit and register it in Context

   function Get_Unit
     (Context           : Analysis_Context;
      Filename, Charset : String;
      Reparse           : Boolean;
      Init_Parser       :
        access procedure (Unit     : Analysis_Unit;
                          Read_BOM : Boolean;
                          Parser   : in out Parser_Type);
      With_Trivia       : Boolean;
      Rule              : Grammar_Rule)
      return Analysis_Unit;
   --  Helper for Get_From_File and Get_From_Buffer: do all the common work
   --  using Init_Parser to either parse from a file or from a buffer. Return
   --  the resulting analysis unit.

   % if ctx.symbol_literals:
      function Create_Symbol_Literals
        (Symbols : Symbol_Table) return Symbol_Literal_Array;
      --  Create pre-computed symbol literals in Symbols and return them
   % endif

   function Convert
     (TDH      : Token_Data_Handler;
      Token    : Token_Type;
      Raw_Data : Lexer.Token_Data_Type) return Token_Data_Type;
   --  Turn data from TDH and Raw_Data into a user-ready token data record

   ------------------------
   -- Address_To_Id_Maps --
   ------------------------

   --  Those maps are used to give unique ids to lexical envs while pretty
   --  printing them.

   package Address_To_Id_Maps is new Ada.Containers.Hashed_Maps
     (Lexical_Env, Integer, Hash, "=");

   type Dump_Lexical_Env_State is record
      Env_Ids : Address_to_Id_Maps.Map;
      --  Mapping: Lexical_Env -> Integer, used to remember which unique Ids we
      --  assigned to the lexical environments we found.

      Next_Id : Positive := 1;
      --  Id to assign to the next unknown lexical environment

      Root_Env : Lexical_Env;
      --  Lexical environment we consider a root (this is the Root_Scope from
      --  the current analysis context), or null if unknown.
   end record;
   --  Holder for the state of lexical environment dumpers

   function Get_Env_Id
     (E : Lexical_Env; State : in out Dump_Lexical_Env_State) return String;
   --  If E is known, return its unique Id from State. Otherwise, assign it a
   --  new unique Id and return it.

   --------------------
   -- Update_Charset --
   --------------------

   procedure Update_Charset (Unit : Analysis_Unit; Charset : String)
   is
   begin
      if Charset'Length /= 0 then
         Unit.Charset := To_Unbounded_String (Charset);
      end if;
   end Update_Charset;

   ------------
   -- Create --
   ------------

   function Create
     (Charset : String := Default_Charset
      % if ctx.default_unit_provider:
         ; Unit_Provider : Unit_Provider_Access_Cst := null
      % endif
     ) return Analysis_Context
   is
      % if ctx.default_unit_provider:
         P : constant Unit_Provider_Access_Cst :=
           (if Unit_Provider = null
            then ${ctx.default_unit_provider.fqn}
            else Unit_Provider);
      % endif
      Actual_Charset : constant String :=
        (if Charset = "" then Default_Charset else Charset);
      Symbols        : constant Symbol_Table := Create;
      Ret            : Analysis_Context;
   begin
      Ret := new Analysis_Context_Type'
        (Ref_Count  => 1,
         Units_Map  => <>,
         Symbols    => Symbols,
         Charset    => To_Unbounded_String (Actual_Charset),
         Root_Scope => AST_Envs.Create
                         (Parent        => AST_Envs.No_Env_Getter,
                          Node          => null,
                          Is_Refcounted => False),

         % if ctx.default_unit_provider:
         Unit_Provider => P,
         % endif

         % if ctx.symbol_literals:
         Symbol_Literals => Create_Symbol_Literals (Symbols),
         % endif

         Private_Part =>
            new Analysis_Context_Private_Part_Type'(others => <>),

         Discard_Errors_In_Populate_Lexical_Env => <>
        );

      Initialize (Ret.Private_Part.Parser);
      return Ret;
   end Create;

   % if ctx.symbol_literals:

      % for sym, name in ctx.sorted_symbol_literals:
         Text_${name} : aliased constant Text_Type := ${string_repr(sym)};
      % endfor

      Symbol_Literals_Text : array (Symbol_Literal_Type) of Text_Cst_Access :=
      (
         ${(', '.join("{name} => Text_{name}'Access".format(name=name)
                      for sym, name in ctx.sorted_symbol_literals))}
      );

      ----------------------------
      -- Create_Symbol_Literals --
      ----------------------------

      function Create_Symbol_Literals
        (Symbols : Symbol_Table) return Symbol_Literal_Array
      is
         Result : Symbol_Literal_Array;
      begin
         for Literal in Symbol_Literal_Type'Range loop
            declare
               Raw_Text : Text_Type renames
                  Symbol_Literals_Text (Literal).all;
               Text     : constant Text_Type :=
                  % if ctx.symbol_canonicalizer:
                     ${ctx.symbol_canonicalizer.fqn} (Raw_Text)
                  % else:
                     Raw_Text
                  % endif
               ;
            begin
               Result (Literal) := Find (Symbols, Text);
            end;
         end loop;
         return Result;
      end Create_Symbol_Literals;
   % endif

   -------------
   -- Inc_Ref --
   -------------

   procedure Inc_Ref (Context : Analysis_Context) is
   begin
      Context.Ref_Count := Context.Ref_Count + 1;
   end Inc_Ref;

   -------------
   -- Dec_Ref --
   -------------

   procedure Dec_Ref (Context : in out Analysis_Context) is
   begin
      Context.Ref_Count := Context.Ref_Count - 1;
      if Context.Ref_Count = 0 then
         Destroy (Context);
      end if;
   end Dec_Ref;

   --------------------------------------------
   -- Discard_Errors_In_Populate_Lexical_Env --
   --------------------------------------------

   procedure Discard_Errors_In_Populate_Lexical_Env
     (Context : Analysis_Context; Discard : Boolean) is
   begin
      Context.Discard_Errors_In_Populate_Lexical_Env := Discard;
   end Discard_Errors_In_Populate_Lexical_Env;

   -----------------
   -- Create_Unit --
   -----------------

   function Create_Unit
     (Context           : Analysis_Context;
      Filename, Charset : String;
      With_Trivia       : Boolean;
      Rule              : Grammar_Rule) return Analysis_Unit
   is
      Fname : constant Unbounded_String := To_Unbounded_String (Filename);
      Unit  : Analysis_Unit := new Analysis_Unit_Type'
        (Context           => Context,
         Ref_Count         => 1,
         AST_Root          => null,
         File_Name         => Fname,
         Charset           => <>,
         TDH               => <>,
         Diagnostics       => <>,
         With_Trivia       => With_Trivia,
         Is_Env_Populated  => False,
         Has_Filled_Caches => False,
         Rule              => Rule,
         AST_Mem_Pool      => No_Pool,
         Destroyables      => Destroyable_Vectors.Empty_Vector,
         Referenced_Units  => <>,
         Lex_Env_Data_Acc  => new Lex_Env_Data_Type,
         Rebindings        => Env_Rebindings_Vectors.Empty_Vector);
   begin
      Initialize (Unit.TDH, Context.Symbols);
      Context.Units_Map.Insert (Fname, Unit);
      return Unit;
   end Create_Unit;

   --------------
   -- Get_Unit --
   --------------

   function Get_Unit
     (Context           : Analysis_Context;
      Filename, Charset : String;
      Reparse           : Boolean;
      Init_Parser       :
        access procedure (Unit     : Analysis_Unit;
                          Read_BOM : Boolean;
                          Parser   : in out Parser_Type);
      With_Trivia       : Boolean;
      Rule              : Grammar_Rule)
      return Analysis_Unit
   is
      use Units_Maps;

      Fname   : constant Unbounded_String := To_Unbounded_String (Filename);
      Cur     : constant Cursor := Context.Units_Map.Find (Fname);
      Created : constant Boolean := Cur = No_Element;
      Unit    : Analysis_Unit;

      Read_BOM : constant Boolean := Charset'Length = 0;
      --  Unless the caller requested a specific charset for this unit, allow
      --  the lexer to automatically discover the source file encoding before
      --  defaulting to the context-specific one. We do this trying to match a
      --  byte order mark.

      Actual_Charset : Unbounded_String;

   begin
      --  Determine which encoding to use.  The parameter comes first, then the
      --  unit-specific default, then the context-specific one.

      if Charset'Length /= 0 then
         Actual_Charset := To_Unbounded_String (Charset);
      elsif not Created then
         Actual_Charset := Element (Cur).Charset;
      else
         Actual_Charset := Context.Charset;
      end if;

      --  Create the Analysis_Unit if needed

      if Created then
         Unit := Create_Unit (Context, Filename, Charset, With_Trivia, Rule);
      else
         Unit := Element (Cur);
      end if;
      Unit.Charset := Actual_Charset;

      --  (Re)parse it if needed

      if Created
         or else Reparse
         or else (With_Trivia and then not Unit.With_Trivia)
      then
         Do_Parsing (Unit, Read_BOM, Init_Parser);
      end if;

      --  If we're in a reparse, do necessary updates
      if Reparse or else (With_Trivia and then not Unit.With_Trivia) then
         Update_After_Reparse (Unit);
      end if;

      return Unit;
   end Get_Unit;

   --------------
   -- Has_Unit --
   --------------

   function Has_Unit
     (Context       : Analysis_Context;
      Unit_Filename : String) return Boolean is
   begin
      return Context.Units_Map.Contains (To_Unbounded_String (Unit_Filename));
   end Has_Unit;

   ----------------
   -- Do_Parsing --
   ----------------

   procedure Do_Parsing
     (Unit        : Analysis_Unit;
      Read_BOM    : Boolean;
      Init_Parser :
        access procedure (Unit     : Analysis_Unit;
                          Read_BOM : Boolean;
                          Parser   : in out Parser_Type))
   is

      procedure Add_Diagnostic (Message : String);
      --  Helper to add a sloc-less diagnostic to Unit

      --------------------
      -- Add_Diagnostic --
      --------------------

      procedure Add_Diagnostic (Message : String) is
      begin
         Unit.Diagnostics.Append
           ((Sloc_Range => No_Source_Location_Range,
             Message    => To_Unbounded_Wide_Wide_String (To_Text (Message))));
      end Add_Diagnostic;

   begin
      --  Reparsing will invalidate all lexical environments related to this
      --  unit, so destroy all related rebindings as well. This browses AST
      --  nodes, so we have to do this before destroying the AST nodes pool.
      Destroy_Rebindings (Unit.Rebindings'Access);

      --  If we have an AST_Mem_Pool already, we are reparsing. We want to
      --  destroy it to free all the allocated memory.
      if Unit.AST_Root /= null then
         Unit.AST_Root.Destroy;
      end if;
      if Unit.AST_Mem_Pool /= No_Pool then
         Free (Unit.AST_Mem_Pool);
      end if;
      Unit.AST_Root := null;
      Unit.Has_Filled_Caches := False;
      Unit.Diagnostics.Clear;

      --  As (re-)loading a unit can change how any AST node property in the
      --  whole analysis context behaves, we have to invalidate caches. This is
      --  likely overkill, but kill all caches here as it's easy to do.
      --  Likewise for values in logic variables.
      Reset_Caches (Unit.Context);

      --  Now create the parser. This is where lexing occurs, so this is where
      --  we get most "setup" issues: missing input file, bad charset, etc.
      --  If we have such an error, catch it, turn it into diagnostics and
      --  abort parsing.

      declare
         use Ada.Exceptions;
      begin
         Init_Parser (Unit, Read_BOM, Unit.Context.Private_Part.Parser);
      exception
         when Exc : Name_Error =>
            --  This happens when we cannot open the source file for lexing:
            --  return a unit anyway with diagnostics indicating what happens.

            Add_Diagnostic
              (Exception_Message (Exc));
            return;

         when Lexer.Unknown_Charset =>
            Add_Diagnostic
              ("Unknown charset """ & To_String (Unit.Charset) & """");
            return;

         when Lexer.Invalid_Input =>
            --  TODO??? Tell where (as a source location) we failed to decode
            --  the input.
            Add_Diagnostic
              ("Could not decode source as """ & To_String (Unit.Charset)
               & """");
            return;
      end;

      --  We have correctly setup a parser! Now let's parse and return what we
      --  get.

      Unit.AST_Mem_Pool := Create;
      Unit.Context.Private_Part.Parser.Mem_Pool := Unit.AST_Mem_Pool;

      Unit.AST_Root :=
        Parse (Unit.Context.Private_Part.Parser, Rule => Unit.Rule);
      Unit.Diagnostics := Unit.Context.Private_Part.Parser.Diagnostics;
   end Do_Parsing;

   -------------------
   -- Get_From_File --
   -------------------

   function Get_From_File
     (Context     : Analysis_Context;
      Filename    : String;
      Charset     : String := "";
      Reparse     : Boolean := False;
      With_Trivia : Boolean := False;
      Rule        : Grammar_Rule :=
         ${Name.from_lower(ctx.main_rule_name)}_Rule)
      return Analysis_Unit
   is
      procedure Init_Parser
        (Unit     : Analysis_Unit;
         Read_BOM : Boolean;
         Parser   : in out Parser_Type)
      is
      begin
         Init_Parser_From_File
           (Filename, To_String (Unit.Charset), Read_BOM, Unit,
            With_Trivia, Parser);
      end Init_Parser;
   begin
      return Get_Unit
        (Context, Filename, Charset, Reparse, Init_Parser'Access, With_Trivia,
         Rule);
   end Get_From_File;

   ---------------------
   -- Get_From_Buffer --
   ---------------------

   function Get_From_Buffer
     (Context     : Analysis_Context;
      Filename    : String;
      Charset     : String := "";
      Buffer      : String;
      With_Trivia : Boolean := False;
      Rule        : Grammar_Rule :=
         ${Name.from_lower(ctx.main_rule_name)}_Rule)
      return Analysis_Unit
   is
      procedure Init_Parser
        (Unit     : Analysis_Unit;
         Read_BOM : Boolean;
         Parser   : in out Parser_Type)
      is
      begin
         Init_Parser_From_Buffer
           (Buffer, To_String (Unit.Charset), Read_BOM, Unit,
            With_Trivia, Parser);
      end Init_Parser;
   begin
      return Get_Unit (Context, Filename, Charset, True, Init_Parser'Access,
                       With_Trivia, Rule);
   end Get_From_Buffer;

   % if ctx.default_unit_provider:

   -----------------------
   -- Get_From_Provider --
   -----------------------

   function Get_From_Provider
     (Context     : Analysis_Context;
      Name        : Text_Type;
      Kind        : Unit_Kind;
      Charset     : String := "";
      Reparse     : Boolean := False;
      With_Trivia : Boolean := False)
      return Analysis_Unit
   is
   begin
      return Context.Unit_Provider.Get_Unit
        (Context, Name, Kind, Charset, Reparse, With_Trivia);

   exception
      when Property_Error =>
         raise Invalid_Unit_Name_Error with
            "Invalid unit name: " & Image (Name, With_Quotes => True)
            & " (" & Unit_Kind'Image (Kind) & ")";
   end Get_From_Provider;

   % endif

   --------------------
   -- Get_With_Error --
   --------------------

   function Get_With_Error
     (Context     : Analysis_Context;
      Filename    : String;
      Error       : String;
      Charset     : String := "";
      With_Trivia : Boolean := False;
      Rule        : Grammar_Rule :=
         ${Name.from_lower(ctx.main_rule_name)}_Rule)
      return Analysis_Unit
   is
      use Units_Maps;

      Fname : constant Unbounded_String := To_Unbounded_String (Filename);
      Cur   : constant Cursor := Context.Units_Map.Find (Fname);
   begin
      if Cur = No_Element then
         declare
            Unit : constant Analysis_Unit :=
               Create_Unit (Context, Filename, Charset, With_Trivia, Rule);
            Msg  : constant Text_Type := To_Text (Error);
         begin
            Unit.Diagnostics.Append
              ((Sloc_Range => No_Source_Location_Range,
                Message    => To_Unbounded_Wide_Wide_String (Msg)));
            return Unit;
         end;
      else
         return Element (Cur);
      end if;
   end Get_With_Error;

   ------------
   -- Remove --
   ------------

   procedure Remove (Context   : Analysis_Context;
                     File_Name : String)
   is
      use Units_Maps;

      Cur : Cursor := Context.Units_Map.Find (To_Unbounded_String (File_Name));
   begin
      if Cur = No_Element then
         raise Constraint_Error with "No such analysis unit";
      end if;

      --  We remove the corresponding analysis unit from this context but
      --  users could keep references on it, so make sure it can live
      --  independently.

      declare
         Unit : constant Analysis_Unit := Element (Cur);
      begin
         --  whole analysis context behaves, we have to invalidate caches. This
         --  is likely overkill, but kill all caches here as it's easy to do.
         Analysis.Reset_Caches (Unit.Context);

         --  Remove all lexical environment artifacts from this analysis unit
         Remove_Exiled_Entries (Unit.Lex_Env_Data_Acc);

         Unit.Context := null;
         Dec_Ref (Unit);
      end;

      Context.Units_Map.Delete (Cur);
   end Remove;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Context : in out Analysis_Context) is
      procedure Free is new Ada.Unchecked_Deallocation
        (Analysis_Context_Private_Part_Type, Analysis_Context_Private_Part);
   begin
      --  Reset caches upfront as we can't do that when destroying units one
      --  after the other.
      Reset_Caches (Context);

      for Unit of Context.Units_Map loop
         Unit.Context := null;
         Dec_Ref (Unit);
      end loop;
      AST_Envs.Destroy (Context.Root_Scope);

      Destroy (Context.Symbols);

      --  Free resources associated to the private part
      Destroy (Context.Private_Part.Parser);
      Free (Context.Private_Part);

      Free (Context);
   end Destroy;

   ------------------
   -- Reset_Caches --
   ------------------

   procedure Reset_Caches (Context : Analysis_Context) is
   begin
      for Unit of Context.Units_Map loop
         Reset_Caches (Unit);
      end loop;
   end Reset_Caches;

   ------------------------
   -- Destroy_Rebindings --
   ------------------------

   procedure Destroy_Rebindings
     (Rebindings : access Env_Rebindings_Vectors.Vector)
   is
      procedure Destroy is new Ada.Unchecked_Deallocation
        (Env_Rebindings_Type, Env_Rebindings);

      procedure Recurse (R : Env_Rebindings);
      --  Destroy R's children and then destroy R. It is up to the caller to
      --  remove R from its parent's Children vector.

      procedure Unregister
        (R          : Env_Rebindings;
         Rebindings : in out Env_Rebindings_Vectors.Vector);
      --  Remove R from Rebindings

      -------------
      -- Recurse --
      -------------

      procedure Recurse (R : Env_Rebindings) is
      begin
         for C of R.Children loop
            Recurse (C);
         end loop;
         R.Children.Destroy;

         Unregister (R, R.Old_Env.Node.Unit.Rebindings);
         Unregister (R, R.New_Env.Node.Unit.Rebindings);

         declare
            Var_R : Env_Rebindings := R;
         begin
            Destroy (Var_R);
         end;
      end Recurse;

      ----------------
      -- Unregister --
      ----------------

      procedure Unregister
        (R          : Env_Rebindings;
         Rebindings : in out Env_Rebindings_Vectors.Vector) is
      begin
         for I in 1 .. Rebindings.Length loop
            if Rebindings.Get (I) = R then
               Rebindings.Pop (I);
               return;
            end if;
         end loop;

         --  We are always supposed to find R in Rebindings, so this should be
         --  unreachable.
         raise Program_Error;
      end Unregister;

   begin
      while Rebindings.Length > 0 loop
         declare
            R : constant Env_Rebindings := Rebindings.Get (1);
         begin
            --  Here, we basically undo what has been done in AST_Envs.Append

            --  If this rebinding has no parent, then during its creation we
            --  registered it in its Old_Env. Otherwise, it is registered
            --  in its Parent's Children list.
            if R.Parent = null then
               R.Old_Env.Rebindings_Pool.Delete (R.New_Env);
            else
               Unregister (R, R.Parent.Children);
            end if;

            --  In all cases it's registered in Old_Env's and New_Env's units
            Recurse (R);
         end;
      end loop;
   end Destroy_Rebindings;

   -------------
   -- Inc_Ref --
   -------------

   procedure Inc_Ref (Unit : Analysis_Unit) is
   begin
      Unit.Ref_Count := Unit.Ref_Count + 1;
   end Inc_Ref;

   -------------
   -- Dec_Ref --
   -------------

   procedure Dec_Ref (Unit : Analysis_Unit) is
   begin
      Unit.Ref_Count := Unit.Ref_Count - 1;
      if Unit.Ref_Count = 0 then
         Destroy (Unit);
      end if;
   end Dec_Ref;

   ---------------------------
   -- Remove_Exiled_Entries --
   ---------------------------

   procedure Remove_Exiled_Entries (Self : Lex_Env_Data) is
   begin
      for El of Self.Is_Contained_By loop
         AST_Envs.Remove (El.Env, El.Key, El.Node);
      end loop;
      Self.Is_Contained_By.Clear;
   end Remove_Exiled_Entries;

   --------------------------
   -- Reroot_Foreign_Nodes --
   --------------------------

   procedure Reroot_Foreign_Nodes
     (Self : Lex_Env_Data; Root_Scope : Lexical_Env)
   is
      Els : ${root_node_type_name}_Vectors.Elements_Array :=
         Self.Contains.To_Array;
      Env : Lexical_Env;
   begin
      for El of Els loop
         Env := El.Pre_Env_Actions (El.Self_Env, Root_Scope, True);
         El.Post_Env_Actions (Env, Root_Scope);
      end loop;
   end Reroot_Foreign_Nodes;

   --------------------------
   -- Update_After_Reparse --
   --------------------------

   procedure Update_After_Reparse (Unit : Analysis_Unit)
   is
   begin
      if Unit.Is_Env_Populated then

         --  Reset the flag so that Populate_Lexical_Env does its work
         Unit.Is_Env_Populated := False;

         --  First we'll remove old entries referencing the old translation
         --  unit in foreign lexical envs.
         Remove_Exiled_Entries (Unit.Lex_Env_Data_Acc);

         --  Then we'll recreate the lexical env structure for the newly parsed
         --  unit.
         Populate_Lexical_Env (Unit);

         --  Finally, any entry that was rooted in one of the unit's lex envs
         --  needs to be re-rooted.
         Reroot_Foreign_Nodes
           (Unit.Lex_Env_Data_Acc, Unit.Context.Root_Scope);

      end if;
   end Update_After_Reparse;

   -------------
   -- Reparse --
   -------------

   procedure Reparse
     (Unit    : Analysis_Unit;
      Charset : String := "")
   is
      procedure Init_Parser
        (Unit     : Analysis_Unit;
         Read_BOM : Boolean;
         Parser   : in out Parser_Type)
      is
      begin
         Init_Parser_From_File
           (To_String (Unit.File_Name),
            To_String (Unit.Charset),
            Read_BOM, Unit, Unit.With_Trivia, Parser);
      end Init_Parser;
   begin
      Update_Charset (Unit, Charset);
      Do_Parsing (Unit, Charset'Length = 0, Init_Parser'Access);
      Update_After_Reparse (Unit);
   end Reparse;

   -------------
   -- Reparse --
   -------------

   procedure Reparse
     (Unit    : Analysis_Unit;
      Charset : String := "";
      Buffer  : String)
   is
      procedure Init_Parser
        (Unit     : Analysis_Unit;
         Read_BOM : Boolean;
         Parser   : in out Parser_Type)
      is
      begin
         Init_Parser_From_Buffer
           (Buffer, To_String (Unit.Charset), Read_BOM,
            Unit, Unit.With_Trivia, Parser);
      end Init_Parser;
   begin
      Update_Charset (Unit, Charset);
      Do_Parsing (Unit, Charset'Length = 0, Init_Parser'Access);
      Unit.Charset := To_Unbounded_String (Charset);
      Update_After_Reparse (Unit);
   end Reparse;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Unit : Analysis_Unit) is
      Unit_Var : Analysis_Unit := Unit;
   begin
      Destroy (Unit.Lex_Env_Data_Acc);
      Analysis_Unit_Sets.Destroy (Unit.Referenced_Units);

      Destroy_Rebindings (Unit.Rebindings'Access);
      Unit.Rebindings.Destroy;

      if Unit.AST_Root /= null then
         Destroy (Unit.AST_Root);
      end if;

      Free (Unit.TDH);
      Free (Unit.AST_Mem_Pool);
      for D of Unit.Destroyables loop
         D.Destroy (D.Object);
      end loop;
      Destroyable_Vectors.Destroy (Unit.Destroyables);
      Free (Unit_Var);
   end Destroy;

   -----------
   -- Print --
   -----------

   procedure Print (Unit : Analysis_Unit) is
   begin
      if Unit.AST_Root = null then
         Put_Line ("<empty analysis unit>");
      else
         Unit.AST_Root.Print;
      end if;
   end Print;

   ---------------
   -- PP_Trivia --
   ---------------

   procedure PP_Trivia (Unit : Analysis_Unit) is

      procedure Process (Trivia : Token_Index) is
         Data : constant Lexer.Token_Data_Type :=
            Unit.TDH.Trivias.Get (Natural (Trivia)).T;
      begin
         Put_Line (Image (Text (Unit.TDH, Data)));
      end Process;

      Last_Token : constant Token_Index :=
         Token_Index (Token_Vectors.Last_Index (Unit.TDH.Tokens) - 1);
      --  Index for the last token in Unit excluding the Termination token
      --  (hence the -1).
   begin
      for Tok of Get_Leading_Trivias (Unit.TDH) loop
         Process (Tok);
      end loop;

      PP_Trivia (Unit.AST_Root);

      for Tok of Get_Trivias (Unit.TDH, Last_Token) loop
         Process (Tok);
      end loop;
   end PP_Trivia;

   --------------------------
   -- Populate_Lexical_Env --
   --------------------------

   procedure Populate_Lexical_Env (Unit : Analysis_Unit) is
   begin
      --  TODO??? Handle env invalidation when reparsing a unit and when a
      --  previous call raised a Property_Error.
      if Unit.Is_Env_Populated then
         return;
      end if;
      Unit.Is_Env_Populated := True;

      begin
         Populate_Lexical_Env (Unit.AST_Root, Unit.Context.Root_Scope);
      exception
         when Property_Error =>
            if not Unit.Context.Discard_Errors_In_Populate_Lexical_Env then
               raise;
            end if;
      end;
   end Populate_Lexical_Env;

   ---------------------
   -- Pre_Env_Actions --
   ---------------------

   function Pre_Env_Actions
     (Self                : access ${root_node_value_type};
      Bound_Env, Root_Env : AST_Envs.Lexical_Env;
      Add_To_Env_Only     : Boolean := False) return AST_Envs.Lexical_Env
   is (null);

   ---------------------
   -- Is_Visible_From --
   ---------------------

   function Is_Visible_From
     (Referenced_Env, Base_Env : AST_Envs.Lexical_Env) return Boolean is
      Referenced_Node : constant ${root_node_type_name} := Referenced_Env.Node;
      Base_Node       : constant ${root_node_type_name} := Base_Env.Node;
   begin
      if Referenced_Node = null then
         raise Property_Error with
            "referenced environment does not belong to any analysis unit";
      elsif Base_Node = null then
         raise Property_Error with
            "base environment does not belong to any analysis unit";
      end if;
      return Is_Referenced_From (Referenced_Node.Unit, Base_Node.Unit);
   end Is_Visible_From;

   ---------------------
   -- Has_Diagnostics --
   ---------------------

   function Has_Diagnostics (Unit : Analysis_Unit) return Boolean is
   begin
      return not Unit.Diagnostics.Is_Empty;
   end Has_Diagnostics;

   -----------------
   -- Diagnostics --
   -----------------

   function Diagnostics (Unit : Analysis_Unit) return Diagnostics_Array is
      Result : Diagnostics_Array (1 .. Natural (Unit.Diagnostics.Length));
      I      : Natural := 1;
   begin
      for D of Unit.Diagnostics loop
         Result (I) := D;
         I := I + 1;
      end loop;
      return Result;
   end Diagnostics;

   ----------------------
   -- Dump_Lexical_Env --
   ----------------------

   procedure Dump_Lexical_Env (Unit : Analysis_Unit) is
   begin
      Dump_Lexical_Env (Unit.AST_Root, Unit.Context.Root_Scope);
   end Dump_Lexical_Env;

   --------------------------
   -- Register_Destroyable --
   --------------------------

   procedure Register_Destroyable_Helper
     (Unit    : Analysis_Unit;
      Object  : System.Address;
      Destroy : Destroy_Procedure)
   is
   begin
      Destroyable_Vectors.Append (Unit.Destroyables, (Object, Destroy));
   end Register_Destroyable_Helper;

   % if ctx.default_unit_provider:
   -------------------
   -- Unit_Provider --
   -------------------

   function Unit_Provider
     (Context : Analysis_Context)
      return Unit_Provider_Access_Cst is (Context.Unit_Provider);
   % endif

   ----------------
   -- Token_Data --
   ----------------

   function Token_Data (Unit : Analysis_Unit) return Token_Data_Handler_Access
   is (Unit.TDH'Access);

   ----------
   -- Root --
   ----------

   function Root (Unit : Analysis_Unit) return ${root_node_type_name} is
     (Unit.AST_Root);

   -----------------
   -- First_Token --
   -----------------

   function First_Token (Unit : Analysis_Unit) return Token_Type is
     (First_Token (Unit.TDH'Access));

   ----------------
   -- Last_Token --
   ----------------

   function Last_Token (Unit : Analysis_Unit) return Token_Type is
     (Last_Token (Unit.TDH'Access));

   -----------------
   -- Token_Count --
   -----------------

   function Token_Count (Unit : Analysis_Unit) return Natural is
     (Unit.TDH.Tokens.Length);

   ------------------
   -- Trivia_Count --
   ------------------

   function Trivia_Count (Unit : Analysis_Unit) return Natural is
     (Unit.TDH.Trivias.Length);

   -----------------
   -- Get_Context --
   -----------------

   function Get_Context (Unit : Analysis_Unit) return Analysis_Context is
     (Unit.Context);

   ------------------
   -- Get_Filename --
   ------------------

   function Get_Filename (Unit : Analysis_Unit) return String is
     (To_String (Unit.File_Name));

   -----------------------
   -- Set_Filled_Caches --
   -----------------------

   procedure Set_Filled_Caches (Unit : Analysis_Unit)
   is
   begin
      Unit.Has_Filled_Caches := True;
   end Set_Filled_Caches;

   --------------
   -- Get_Unit --
   --------------

   function Get_Unit
     (Node : access ${root_node_value_type}'Class)
      return Analysis_Unit
   is
   begin
      return Node.Unit;
   end Get_Unit;

   --------------------
   -- Reference_Unit --
   --------------------

   procedure Reference_Unit (From, Referenced : Analysis_Unit) is
      Dummy : Boolean;
   begin
      Dummy := Analysis_Unit_Sets.Add (From.Referenced_Units, Referenced);
   end Reference_Unit;

   ------------------------
   -- Is_Referenced_From --
   ------------------------

   function Is_Referenced_From
     (Referenced, Unit : Analysis_Unit) return Boolean
   is
   begin
      if Unit = null or else Referenced = null then
         return False;
      elsif Unit = Referenced then
         return True;
      else
         return Analysis_Unit_Sets.Has (Unit.Referenced_Units, Referenced);
      end if;
   end Is_Referenced_From;

   ----------------------
   -- Get_Lex_Env_Data --
   ----------------------

   function Get_Lex_Env_Data
     (Unit : Analysis_Unit) return Lex_Env_Data
   is
   begin
      return Unit.Lex_Env_Data_Acc;
   end Get_Lex_Env_Data;

   ------------------------------
   -- Register_Destroyable_Gen --
   ------------------------------

   procedure Register_Destroyable_Gen
     (Unit : Analysis_Unit; Object : T_Access)
   is
      function Convert is new Ada.Unchecked_Conversion
        (System.Address, Destroy_Procedure);
      procedure Destroy_Procedure (Object : in out T_Access) renames Destroy;
   begin
      Register_Destroyable_Helper
        (Unit,
         Object.all'Address,
         Convert (Destroy_Procedure'Address));
   end Register_Destroyable_Gen;

   ------------------
   -- Reset_Caches --
   ------------------

   procedure Reset_Caches (Unit : Analysis_Unit) is

      -----------
      -- Visit --
      -----------

      function Visit
        (Node : access ${root_node_value_type}'Class) return Visit_Status is
      begin
         Node.Reset_Caches;
         return Into;
      end Visit;

   begin
      if Unit.Has_Filled_Caches and Unit.AST_Root /= null then
         Unit.AST_Root.Traverse (Visit'Access);
      end if;
      Unit.Has_Filled_Caches := False;
   end Reset_Caches;

   ${array_types.body(T.LexicalEnv.array)}
   ${array_types.body(T.root_node.entity.array)}

   function Lookup_Internal
     (Node : ${root_node_type_name};
      Sloc : Source_Location;
      Snap : Boolean := False) return ${root_node_type_name};
   procedure Lookup_Relative
     (Node       : ${root_node_type_name};
      Sloc       : Source_Location;
      Position   : out Relative_Position;
      Node_Found : out ${root_node_type_name};
      Snap       : Boolean := False);
   --  Implementation helpers for the looking up process

   -----------------
   -- Set_Parents --
   -----------------

   procedure Set_Parents
     (Node, Parent : access ${root_node_value_type}'Class)
   is
   begin
      if Node = null then
         return;
      end if;

      Node.Parent := ${root_node_type_name} (Parent);

      for I in 1 .. Node.Child_Count loop
         Set_Parents (Node.Child (I), Node);
      end loop;
   end Set_Parents;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Node : access ${root_node_value_type}'Class) is
   begin
      if Node = null then
         return;
      end if;

      Node.Free_Extensions;
      Node.Reset_Caches;
      for I in 1 .. Node.Child_Count loop
         Destroy (Node.Child (I));
      end loop;
   end Destroy;

   -----------
   -- Child --
   -----------

   function Child (Node  : access ${root_node_value_type}'Class;
                   Index : Positive) return ${root_node_type_name}
   is
      Result          : ${root_node_type_name};
      Index_In_Bounds : Boolean;
   begin
      Get_Child (Node, Index, Index_In_Bounds, Result);
      return (if Index_In_Bounds then Result else null);
   end Child;

   --------------
   -- Traverse --
   --------------

   function Traverse
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class)
              return Visit_Status)
     return Visit_Status
   is
      Status : Visit_Status := Into;

   begin
      if Node /= null then
         Status := Visit (Node);

         --  Skip processing the child nodes if the returned status is Over
         --  or Stop. In the former case the previous call to Visit has taken
         --  care of processing the needed childs, and in the latter case we
         --  must immediately stop processing the tree.

         if Status = Into then
            for I in 1 .. Child_Count (Node) loop
               declare
                  Cur_Child : constant ${root_node_type_name} :=
                     Child (Node, I);

               begin
                  if Cur_Child /= null then
                     Status := Traverse (Cur_Child, Visit);
                     exit when Status /= Into;
                  end if;
               end;
            end loop;
         end if;
      end if;

      if Status = Stop then
         return Stop;

      --  At this stage the Over status has no sense and we just continue
      --  processing the tree.

      else
         return Into;
      end if;
   end Traverse;

   --------------
   -- Traverse --
   --------------

   procedure Traverse
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class)
                               return Visit_Status)
   is
      Result_Status : Visit_Status;
      pragma Unreferenced (Result_Status);
   begin
      Result_Status := Traverse (Node, Visit);
   end Traverse;

   ------------------------
   -- Traverse_With_Data --
   ------------------------

   function Traverse_With_Data
     (Node  : access ${root_node_value_type}'Class;
      Visit : access function (Node : access ${root_node_value_type}'Class;
                               Data : in out Data_type)
                               return Visit_Status;
      Data  : in out Data_Type)
      return Visit_Status
   is
      function Helper (Node : access ${root_node_value_type}'Class)
                       return Visit_Status;

      ------------
      -- Helper --
      ------------

      function Helper (Node : access ${root_node_value_type}'Class)
                       return Visit_Status
      is
      begin
         return Visit (Node, Data);
      end Helper;

      Saved_Data : Data_Type;
      Result     : Visit_Status;

   begin
      if Reset_After_Traversal then
         Saved_Data := Data;
      end if;
      Result := Traverse (Node, Helper'Access);
      if Reset_After_Traversal then
         Data := Saved_Data;
      end if;
      return Result;
   end Traverse_With_Data;

   --------------
   -- Traverse --
   --------------

   function Traverse
     (Root : access ${root_node_value_type}'Class)
      return Traverse_Iterator
   is
   begin
      return Create (Root);
   end Traverse;

   ----------------
   -- Get_Parent --
   ----------------

   function Get_Parent
     (N : ${root_node_type_name}) return ${root_node_type_name}
   is (N.Parent);

   ------------------------------------
   -- First_Child_Index_For_Traverse --
   ------------------------------------

   function First_Child_Index_For_Traverse
     (N : ${root_node_type_name}) return Natural
   is (N.First_Child_Index);

   -----------------------------------
   -- Last_Child_Index_For_Traverse --
   -----------------------------------

   function Last_Child_Index_For_Traverse
     (N : ${root_node_type_name}) return Natural
   is (N.Last_Child_Index);

   ---------------
   -- Get_Child --
   ---------------

   function Get_Child
     (N : ${root_node_type_name}; I : Natural) return ${root_node_type_name}
   is (N.Child (I));

   ----------
   -- Next --
   ----------

   function Next (It       : in out Find_Iterator;
                  Element  : out ${root_node_type_name}) return Boolean
   is
   begin
      while Next (It.Traverse_It, Element) loop
         if It.Predicate.Evaluate (Element) then
            return True;
         end if;
      end loop;
      return False;
   end Next;

   --------------
   -- Finalize --
   --------------

   overriding procedure Finalize (It : in out Find_Iterator) is
   begin
      Destroy (It.Predicate);
   end Finalize;

   ----------
   -- Next --
   ----------

   overriding function Next
     (It      : in out Local_Find_Iterator;
      Element : out ${root_node_type_name})
      return Boolean
   is
   begin
      while Next (It.Traverse_It, Element) loop
         if It.Predicate (Element) then
            return True;
         end if;
      end loop;
      return False;
   end Next;

   ----------
   -- Find --
   ----------

   function Find
     (Root      : access ${root_node_value_type}'Class;
      Predicate : access function (N : ${root_node_type_name}) return Boolean)
     return Local_Find_Iterator
   is
      Dummy  : ${root_node_type_name};
      Ignore : Boolean;
   begin
      return Ret : Local_Find_Iterator
        := Local_Find_Iterator'
          (Ada.Finalization.Limited_Controlled with
           Traverse_It => Traverse (Root),

           --  We still want to provide this functionality, even though it is
           --  unsafe. TODO: We might be able to make a safe version of this
           --  using generics. Still would be more verbose though.
           Predicate   => Predicate'Unrestricted_Access.all)
      do
         Ignore := Next (Ret.Traverse_It, Dummy);

      end return;
   end Find;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Self : in out Lex_Env_Data_Type) is
   begin
      Self.Is_Contained_By.Destroy;
      Self.Contains.Destroy;
   end Destroy;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Self : in out Lex_Env_Data) is
      procedure Free is new Ada.Unchecked_Deallocation
        (Lex_Env_Data_Type, Lex_Env_Data);
   begin
      Destroy (Self.all);
      Free (Self);
   end Destroy;

   ----------
   -- Find --
   ----------

   function Find
     (Root      : access ${root_node_value_type}'Class;
      Predicate : ${root_node_type_name}_Predicate)
      return Find_Iterator
   is
      Dummy  : ${root_node_type_name};
      Ignore : Boolean;
   begin
      return Ret : Find_Iterator :=
        (Ada.Finalization.Limited_Controlled with
         Traverse_It => Traverse (Root),
         Predicate   => Predicate)
      do
         Ignore := Next (Ret.Traverse_It, Dummy);
      end return;
   end Find;

   ----------------
   -- Find_First --
   ----------------

   function Find_First
     (Root      : access ${root_node_value_type}'Class;
      Predicate : ${root_node_type_name}_Predicate)
      return ${root_node_type_name}
   is
      I      : Find_Iterator := Find (Root, Predicate);
      Result : ${root_node_type_name};
      Dummy  : ${root_node_type_name};
      Ignore : Boolean;
   begin
      Ignore := Next (I.Traverse_It, Dummy);
      --  Ignore first result
      if not I.Next (Result) then
         Result := null;
      end if;
      return Result;
   end Find_First;

   --------------
   -- Evaluate --
   --------------

   function Evaluate
     (P : access ${root_node_type_name}_Kind_Filter;
      N : ${root_node_type_name})
      return Boolean
   is
   begin
      return N.Kind = P.Kind;
   end Evaluate;

   ----------------
   -- Sloc_Range --
   ----------------

   function Sloc_Range
     (Node : access ${root_node_value_type}'Class;
      Snap : Boolean := False) return Source_Location_Range
   is
      TDH                  : Token_Data_Handler renames Node.Unit.TDH;
      Sloc_Start, Sloc_End : Source_Location;

      function Get
        (Index : Token_Index) return Lexer.Token_Data_Type is
        (Get_Token (TDH, Index));

   begin
      if Node.Is_Synthetic then
         return Sloc_Range (Node.Parent);
      end if;

      --  Snapping: We'll go one token before the start token, and one token
      --  after the end token, and the sloc range will extend from the end of
      --  the start token to the start of the end token, including any
      --  whitespace and trivia that might be surrounding the node.
      --
      --  TODO: Only nodes we're gonna try to snap are nodes with default
      --  anchors. However, we can make the logic more specific, eg:
      --
      --  * If the start anchor is beginning, then snap the start sloc.
      --
      --  * If the end anchor is ending, then snap the end sloc.
      --
      --  This way composite cases can work too.

      if Snap then
         declare
            Tok_Start : constant Token_Index :=
              Token_Index'Max (Node.Token_Start_Index - 1, 0);
            Tok_End : constant Token_Index :=
              Token_Index'Min (Node.Token_End_Index + 1, Last_Token (TDH));
         begin
            Sloc_Start := End_Sloc (Get (Tok_Start).Sloc_Range);
            Sloc_End := Start_Sloc (Get (Tok_End).Sloc_Range);
         end;
      else
         Sloc_Start := Start_Sloc (Get (Node.Token_Start_Index).Sloc_Range);
         Sloc_End :=
           (if Node.Token_End_Index /= No_Token_Index
            then End_Sloc (Get (Node.Token_End_Index).Sloc_Range)
            else Start_Sloc (Get (Node.Token_Start_Index).Sloc_Range));
      end if;
      return Make_Range (Sloc_Start, Sloc_End);
   end Sloc_Range;

   ------------
   -- Lookup --
   ------------

   function Lookup (Node : access ${root_node_value_type}'Class;
                    Sloc : Source_Location;
                    Snap : Boolean := False) return ${root_node_type_name}
   is
      Position : Relative_Position;
      Result   : ${root_node_type_name};
   begin
      if Sloc = No_Source_Location then
         return null;
      end if;

      Lookup_Relative
        (${root_node_type_name} (Node), Sloc, Position, Result, Snap);
      return Result;
   end Lookup;

   ---------------------
   -- Lookup_Internal --
   ---------------------

   function Lookup_Internal
     (Node : ${root_node_type_name};
      Sloc : Source_Location;
      Snap : Boolean := False) return ${root_node_type_name}
   is
      --  For this implementation helper (i.e. internal primitive), we can
      --  assume that all lookups fall into this node's sloc range.
      pragma Assert (Compare (Sloc_Range (Node, Snap), Sloc) = Inside);

      Children : constant ${root_node_array.api_name} := Node.Children;
      Pos      : Relative_Position;
      Result   : ${root_node_type_name};
   begin
      --  Look for a child node that contains Sloc (i.e. return the most
      --  precise result).

      for Child of Children loop
         --  Note that we assume here that child nodes are ordered so that the
         --  first one has a sloc range that is before the sloc range of the
         --  second child node, etc.

         if Child /= null then
            Lookup_Relative (Child, Sloc, Pos, Result, Snap);
            case Pos is
               when Before =>
                   --  If this is the first node, Sloc is before it, so we can
                   --  stop here.  Otherwise, Sloc is between the previous
                   --  child node and the next one...  so we can stop here,
                   --  too.
                   return Node;

               when Inside =>
                   return Result;

               when After =>
                   --  Sloc is after the current child node, so see with the
                   --  next one.
                   null;
            end case;
         end if;
      end loop;

      --  If we reach this point, we found no children that covers Sloc, but
      --  Node still covers it (see the assertion).
      return Node;
   end Lookup_Internal;

   -------------
   -- Compare --
   -------------

   function Compare (Node : access ${root_node_value_type}'Class;
                     Sloc : Source_Location;
                     Snap : Boolean := False) return Relative_Position is
   begin
      return Compare (Sloc_Range (Node, Snap), Sloc);
   end Compare;

   ---------------------
   -- Lookup_Relative --
   ---------------------

   procedure Lookup_Relative
     (Node       : ${root_node_type_name};
      Sloc       : Source_Location;
      Position   : out Relative_Position;
      Node_Found : out ${root_node_type_name};
      Snap       : Boolean := False)
   is
      Result : constant Relative_Position :=
        Compare (Node, Sloc, Snap);
   begin
      Position := Result;
      Node_Found := (if Result = Inside
                     then Lookup_Internal (Node, Sloc, Snap)
                     else null);
   end Lookup_Relative;

   -------------------
   -- Get_Extension --
   -------------------

   function Get_Extension
     (Node : access ${root_node_value_type}'Class;
      ID   : Extension_ID;
      Dtor : Extension_Destructor) return Extension_Access
   is
      use Extension_Vectors;
   begin
      for Slot of Node.Extensions loop
         if Slot.ID = ID then
            return Slot.Extension;
         end if;
      end loop;

      declare
         New_Ext : constant Extension_Access :=
           new Extension_Type'(Extension_Type (System.Null_Address));
      begin
         Append (Node.Extensions,
                 Extension_Slot'(ID        => ID,
                                 Extension => New_Ext,
                                 Dtor      => Dtor));
         return New_Ext;
      end;
   end Get_Extension;

   ---------------------
   -- Free_Extensions --
   ---------------------

   procedure Free_Extensions (Node : access ${root_node_value_type}'Class) is
      procedure Free is new Ada.Unchecked_Deallocation
        (Extension_Type, Extension_Access);
      use Extension_Vectors;
      Slot : Extension_Slot;
   begin
      --  Explicit iteration for perf
      for J in First_Index (Node.Extensions) .. Last_Index (Node.Extensions)
      loop
         Slot := Get (Node.Extensions, J);
         Slot.Dtor (Node, Slot.Extension.all);
         Free (Slot.Extension);
      end loop;
   end Free_Extensions;

   --------------
   -- Children --
   --------------

   function Children
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_array.api_name}
   is
      First : constant Integer
        := ${root_node_array.index_type()}'First;
      Last  : constant Integer := First + Child_Count (Node) - 1;
   begin
      return A : ${root_node_array.api_name} (First .. Last)
      do
         for I in First .. Last loop
            A (I) := Child (Node, I);
         end loop;
      end return;
   end Children;

   function Children
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_array.name}
   is
      C : ${root_node_array.api_name} := Children (Node);
   begin
      return Ret : ${root_node_array.name} := Create (C'Length) do
         Ret.Items := C;
      end return;
   end Children;

   -----------------
   -- First_Token --
   -----------------

   function First_Token (TDH : Token_Data_Handler_Access) return Token_Type is
      use Token_Vectors, Trivia_Vectors, Token_Data_Handlers.Integer_Vectors;
   begin
      if Length (TDH.Tokens_To_Trivias) = 0
         or else (First_Element (TDH.Tokens_To_Trivias)
                  = Integer (No_Token_Index))
      then
         --  There is no leading trivia: return the first token

         return (if Length (TDH.Tokens) = 0
                 then No_Token
                 else (TDH,
                       Token_Index (First_Index (TDH.Tokens)),
                       No_Token_Index));

      else
         return (TDH, No_Token_Index, Token_Index (First_Index (TDH.Trivias)));
      end if;
   end First_Token;

   ----------------
   -- Last_Token --
   ----------------

   function Last_Token (TDH : Token_Data_Handler_Access) return Token_Type is
      use Token_Vectors, Trivia_Vectors, Token_Data_Handlers.Integer_Vectors;
   begin
      if Length (TDH.Tokens_To_Trivias) = 0
           or else
         Last_Element (TDH.Tokens_To_Trivias) = Integer (No_Token_Index)
      then
         --  There is no trailing trivia: return the last token

         return (if Length (TDH.Tokens) = 0
                 then No_Token
                 else (TDH,
                       Token_Index (Last_Index (TDH.Tokens)),
                       No_Token_Index));

      else
         return (TDH, No_Token_Index, Token_Index (First_Index (TDH.Trivias)));
      end if;
   end Last_Token;

   ---------
   -- "<" --
   ---------

   function "<" (Left, Right : Token_Type) return Boolean is
      pragma Assert (Left.TDH = Right.TDH);
   begin
      if Left.Token < Right.Token then
         return True;

      elsif Left.Token = Right.Token then
         return Left.Trivia < Right.Trivia;

      else
         return False;
      end if;
   end "<";

   ----------
   -- Next --
   ----------

   function Next (Token : Token_Type) return Token_Type is
   begin
      if Token.TDH = null then
         return No_Token;
      end if;

      declare
         use Token_Vectors, Trivia_Vectors,
             Token_Data_Handlers.Integer_Vectors;
         TDH : Token_Data_Handler renames Token.TDH.all;

         function Next_Token return Token_Type is
           (if Token.Token < Token_Index (Last_Index (TDH.Tokens))
            then (Token.TDH, Token.Token + 1, No_Token_Index)
            else No_Token);
         --  Return a reference to the next token (not trivia) or No_Token if
         --  Token was the last one.

      begin
         if Token.Trivia /= No_Token_Index then
            --  Token is a reference to a trivia: take the next trivia if it
            --  exists, or escalate to the next token otherwise.

            declare
               Tr : constant Trivia_Node :=
                  Get (TDH.Trivias, Natural (Token.Trivia));
            begin
               return (if Tr.Has_Next
                       then (Token.TDH, Token.Token, Token.Trivia + 1)
                       else Next_Token);
            end;

         else
            --  Thanks to the guard above, we cannot get to the declare block
            --  for the No_Token case, so if Token does not refers to a trivia,
            --  it must be a token.

            pragma Assert (Token.Token /= No_Token_Index);

            --  If there is no trivia, just go to the next token

            if Length (TDH.Tokens_To_Trivias) = 0 then
               return Next_Token;
            end if;

            --  If this token has trivia, return a reference to the first one,
            --  otherwise get the next token.

            declare
               Tr_Index : constant Token_Index := Token_Index
                 (Get (TDH.Tokens_To_Trivias, Natural (Token.Token) + 1));
            begin
               return (if Tr_Index = No_Token_Index
                       then Next_Token
                       else (Token.TDH, Token.Token, Tr_Index));
            end;
         end if;
      end;
   end Next;

   --------------
   -- Previous --
   --------------

   function Previous (Token : Token_Type) return Token_Type is
   begin
      if Token.TDH = null then
         return No_Token;
      end if;

      declare
         use Token_Vectors, Trivia_Vectors,
             Token_Data_Handlers.Integer_Vectors;
         TDH : Token_Data_Handler renames Token.TDH.all;
      begin
         if Token.Trivia = No_Token_Index then
            --  Token is a regular token, so the previous token is either the
            --  last trivia of the previous regular token, either the previous
            --  regular token itself.
            declare
               Prev_Trivia : Token_Index;
            begin
               --  Get the index of the trivia that is right bofre Token (if
               --  any).
               if Length (TDH.Tokens_To_Trivias) = 0 then
                  Prev_Trivia := No_Token_Index;

               else
                  Prev_Trivia := Token_Index
                    (Get (TDH.Tokens_To_Trivias, Natural (Token.Token)));
                  while Prev_Trivia /= No_Token_Index
                           and then
                        Get (TDH.Trivias, Natural (Prev_Trivia)).Has_Next
                  loop
                     Prev_Trivia := Prev_Trivia + 1;
                  end loop;
               end if;

               --  If there is no such trivia and Token was the first one, then
               --  this was the start of the token stream: no previous token.
               if Prev_Trivia = No_Token_Index
                  and then Token.Token <= First_Token_Index
               then
                  return No_Token;
               else
                  return (Token.TDH, Token.Token - 1, Prev_Trivia);
               end if;
            end;

         --  Past this point: Token is known to be a trivia

         elsif Token.Trivia = First_Token_Index then
            --  This is the first trivia for some token, so the previous token
            --  cannot be a trivia.
            return (if Token.Token = No_Token_Index
                    then No_Token
                    else (Token.TDH, Token.Token, No_Token_Index));

         elsif Token.Token = No_Token_Index then
            --  This is a leading trivia and not the first one, so the previous
            --  token has to be a trivia.
            return (Token.TDH, No_Token_Index, Token.Trivia - 1);

         --  Past this point: Token is known to be a trivia *and* it is not a
         --  leading trivia.

         else
            return (Token.TDH,
                    Token.Token,
                    (if Get (TDH.Trivias, Natural (Token.Trivia - 1)).Has_Next
                     then Token.Trivia - 1
                     else No_Token_Index));
         end if;
      end;
   end Previous;

   ----------------
   -- Get_Symbol --
   ----------------

   function Get_Symbol (Token : Token_Type) return Symbol_Type is
      subtype Token_Data_Reference is
         Token_Data_Handlers.Token_Vectors.Element_Access;

      Token_Data : constant Token_Data_Reference :=
        (if Token.Trivia = No_Token_Index
         then Token_Data_Reference
           (Token.TDH.Tokens.Get_Access (Natural (Token.Token)))
         else Token_Data_Reference'
           (Token.TDH.Trivias.Get_Access
              (Natural (Token.Trivia) - 1).T'Access));
   begin
      return Force_Symbol (Token.TDH.all, Token_Data.all);
   end Get_Symbol;

   -----------------
   -- First_Token --
   -----------------

   function First_Token (Self : Token_Iterator) return Token_Type
   is (Self.Node.Token_Start);

   ----------------
   -- Next_Token --
   ----------------

   function Next_Token
     (Self : Token_Iterator; Tok : Token_Type) return Token_Type
   is (Next (Tok));

   -----------------
   -- Has_Element --
   -----------------

   function Has_Element
     (Self : Token_Iterator; Tok : Token_Type) return Boolean
   is (Tok.Token <= Self.Last);

   -------------
   -- Element --
   -------------

   function Element (Self : Token_Iterator; Tok : Token_Type) return Token_Type
   is (Tok);

   -----------------
   -- Token_Range --
   -----------------

   function Token_Range
     (Node : access ${root_node_value_type}'Class)
      return Token_Iterator
   is
     (Token_Iterator'(${root_node_type_name} (Node), Node.Token_End_Index));

   --------------
   -- Raw_Data --
   --------------

   function Raw_Data (T : Token_Type) return Lexer.Token_Data_Type is
     (if T.Trivia = No_Token_Index
      then Token_Vectors.Get (T.TDH.Tokens, Natural (T.Token))
      else Trivia_Vectors.Get (T.TDH.Trivias, Natural (T.Trivia)).T);

   -------------
   -- Convert --
   -------------

   function Convert
     (TDH      : Token_Data_Handler;
      Token    : Token_Type;
      Raw_Data : Lexer.Token_Data_Type) return Token_Data_Type is
   begin
      return (Kind          => Raw_Data.Kind,
              Is_Trivia     => Token.Trivia /= No_Token_Index,
              Index         => (if Token.Trivia = No_Token_Index
                                then Token.Token
                                else Token.Trivia),
              Source_Buffer => Text_Cst_Access (TDH.Source_Buffer),
              Source_First  => Raw_Data.Source_First,
              Source_Last   => Raw_Data.Source_Last,
              Sloc_Range    => Raw_Data.Sloc_Range);
   end Convert;

   ----------
   -- Data --
   ----------

   function Data (Token : Token_Type) return Token_Data_Type is
   begin
      return Convert (Token.TDH.all, Token, Raw_Data (Token));
   end Data;

   ----------
   -- Text --
   ----------

   function Text (Token : Token_Type) return Text_Type is
      RD : constant Lexer.Token_Data_Type := Raw_Data (Token);
   begin
      return Token.TDH.Source_Buffer (RD.Source_First .. RD.Source_Last);
   end Text;

   ----------
   -- Text --
   ----------

   function Text (First, Last : Token_Type) return Text_Type is
      FD : constant Token_Data_Type := Data (First);
      LD : constant Token_Data_Type := Data (Last);
   begin
      if First.TDH /= Last.TDH then
         raise Constraint_Error;
      end if;
      return FD.Source_Buffer.all (FD.Source_First .. LD.Source_Last);
   end Text;

   ----------
   -- Text --
   ----------

   function Text (Token : Token_Type) return String
   is (Image (Text (Token)));

   ----------
   -- Kind --
   ----------

   function Kind (Token_Data : Token_Data_Type) return Token_Kind is
   begin
      return Token_Data.Kind;
   end Kind;

   ---------------
   -- Is_Trivia --
   ---------------

   function Is_Trivia (Token_Data : Token_Data_Type) return Boolean is
   begin
      return Token_Data.Is_Trivia;
   end Is_Trivia;

   -----------
   -- Index --
   -----------

   function Index (Token_Data : Token_Data_Type) return Token_Index is
   begin
      return Token_Data.Index;
   end Index;

   ----------------
   -- Sloc_Range --
   ----------------

   function Sloc_Range
     (Token_Data : Token_Data_Type) return Source_Location_Range
   is
   begin
      return Token_Data.Sloc_Range;
   end Sloc_Range;

   ----------
   -- Text --
   ----------

   function Text
     (Node : access ${root_node_value_type}'Class) return Text_Type is
   begin
      return Text (Node.Token_Start, Node.Token_End);
   end Text;

   -------------------
   -- Is_Equivalent --
   -------------------

   function Is_Equivalent (L, R : Token_Type) return Boolean is
      DL : constant Token_Data_Type := Data (L);
      DR : constant Token_Data_Type := Data (R);
      TL : constant Text_Type := Text (L);
      TR : constant Text_Type := Text (R);
   begin
      return DL.Kind = DR.Kind and then TL = TR;
   end Is_Equivalent;

   -----------
   -- Image --
   -----------

   function Image (Token : Token_Type) return String is
      D : constant Token_Data_Type := Data (Token);
   begin
      return ("<Token Kind=" & Token_Kind_Name (D.Kind) &
              " Text=" & Image (Text (Token), With_Quotes => True) & ">");
   end Image;

   --------------------------
   -- Children_With_Trivia --
   --------------------------

   function Children_With_Trivia
     (Node : access ${root_node_value_type}'Class) return Children_Array
   is
      package Children_Vectors is new Langkit_Support.Vectors (Child_Record);
      use Children_Vectors;

      Ret_Vec : Children_Vectors.Vector;
      TDH     : Token_Data_Handler renames Node.Unit.TDH;

      procedure Append_Trivias (First, Last : Token_Index);
      --  Append all the trivias of tokens between indices First and Last to
      --  the returned vector.

      procedure Append_Trivias (First, Last : Token_Index) is
      begin
         for I in First .. Last loop
            for D of Get_Trivias (TDH, I) loop
               Append (Ret_Vec, (Kind   => Trivia,
                                 Trivia => (TDH    => Node.Unit.TDH'Access,
                                            Token  => I,
                                            Trivia => D)));
            end loop;
         end loop;
      end Append_Trivias;

      function Filter_Children (N : ${root_node_type_name}) return Boolean is
         --  Get rid of null nodes
        (N /= null
         --  Get rid of nodes with no real existence in the source code
         and then not N.Is_Ghost);

      First_Child : constant ${root_node_array.index_type()} :=
         ${root_node_array.index_type()}'First;
      N_Children  : constant ${root_node_array.api_name}
        := ${root_node_array.api_name}
             (${root_node_type_name}_Arrays.Filter
              (${root_node_array.pkg_vector}.Elements_Array
                (${root_node_array.api_name}'(Children (Node))),
               Filter_Children'Access));
   begin
      if N_Children'Length > 0
        and then (Node.Token_Start_Index
                    /= N_Children (First_Child).Token_Start_Index)
      then
         Append_Trivias (Node.Token_Start_Index,
                         N_Children (First_Child).Token_Start_Index - 1);
      end if;

      for I in N_Children'Range loop
         Append (Ret_Vec, Child_Record'(Child, N_Children (I)));
         Append_Trivias (N_Children (I).Token_End_Index,
                         (if I = N_Children'Last
                          then Node.Token_End_Index - 1
                          else N_Children (I + 1).Token_Start_Index - 1));
      end loop;

      return A : constant Children_Array :=
         Children_Array (To_Array (Ret_Vec))
      do
         --  Don't forget to free Ret_Vec, since its memory is not
         --  automatically managed.
         Destroy (Ret_Vec);
      end return;
   end Children_With_Trivia;

   ---------------
   -- PP_Trivia --
   ---------------

   procedure PP_Trivia
     (Node        : access ${root_node_value_type}'Class;
      Line_Prefix : String := "")
   is
      Children_Prefix : constant String := Line_Prefix & "|  ";
   begin
      Put_Line (Line_Prefix & Kind_Name (Node));
      for C of Children_With_Trivia (Node) loop
         case C.Kind is
            when Trivia =>
               Put_Line (Children_Prefix & Text (C.Trivia));
            when Child =>
               C.Node.PP_Trivia (Children_Prefix);
         end case;
      end loop;
   end PP_Trivia;

   --------------------------
   -- Populate_Lexical_Env --
   --------------------------

   procedure Populate_Lexical_Env
     (Node     : access ${root_node_value_type}'Class;
      Root_Env : AST_Envs.Lexical_Env)
   is

      procedure Populate_Internal
        (Node      : access ${root_node_value_type}'Class;
         Bound_Env : Lexical_Env);

      -----------------------
      -- Populate_Internal --
      -----------------------

      procedure Populate_Internal
        (Node      : access ${root_node_value_type}'Class;
         Bound_Env : Lexical_Env)
      is
         Initial_Env : Lexical_Env;
      begin
         if Node = null then
            return;
         end if;

         --  By default (i.e. unless env actions add a new env),
         --  the environment we store in Node is the current one.
         Node.Self_Env := Bound_Env;

         Initial_Env := Node.Pre_Env_Actions (Bound_Env, Root_Env);

         --  Call recursively on children
         for C of ${root_node_array.api_name}'(Children (Node)) loop
            Populate_Internal (C, Node.Self_Env);
         end loop;

         Node.Post_Env_Actions (Initial_Env, Root_Env);
      end Populate_Internal;

      Env : AST_Envs.Lexical_Env := Root_Env;
   begin
      Populate_Internal (Node, Env);
   end Populate_Lexical_Env;

   -------------------------------
   -- Node_File_And_Sloc_Image  --
   -------------------------------

   function Node_File_And_Sloc_Image
     (Node : ${root_node_type_name}) return Text_Type
   is (To_Text (To_String (Node.Unit.File_Name))
       & ":" & To_Text (Image (Start_Sloc (Sloc_Range (Node)))));

   --------------------------
   -- Raise_Property_Error --
   --------------------------

   procedure Raise_Property_Error (Message : String := "") is
   begin
      if Message'Length = 0 then
         raise Property_Error;
      else
         raise Property_Error with Message;
      end if;
   end Raise_Property_Error;

   -------------------
   -- Is_Rebindable --
   -------------------

   function Is_Rebindable (Node : ${root_node_type_name}) return Boolean is
   begin
      <% rebindable_nodes = [n for n in ctx.astnode_types
                             if n.annotations.rebindable] %>
      % if not rebindable_nodes:
         return True;
      % else:
         <% type_sum = ' | '.join("{}_Type'Class".format(n.name)
                                  for n in rebindable_nodes) %>
         return Node.all in ${type_sum};
      % endif
   end Is_Rebindable;

   ------------------------
   -- Register_Rebinding --
   ------------------------

   procedure Register_Rebinding
     (Node : ${root_node_type_name}; Rebinding : System.Address)
   is
      pragma Warnings (Off, "possible aliasing problem for type");
      function Convert is new Ada.Unchecked_Conversion
        (System.Address, Env_Rebindings);
      pragma Warnings (Off, "possible aliasing problem for type");
   begin
      Node.Unit.Rebindings.Append (Convert (Rebinding));
   end Register_Rebinding;

   --------------------
   -- Element_Parent --
   --------------------

   function Element_Parent
     (Node : ${root_node_type_name}) return ${root_node_type_name}
   is (Node.Parent);

   -----------------
   -- Short_Image --
   -----------------

   function Short_Image
     (Node : access ${root_node_value_type})
      return Text_Type
   is
      Self : access ${root_node_value_type}'Class := Node;
   begin
      return "<" & To_Text (Kind_Name (Self))
             & " " & To_Text (Image (Sloc_Range (Node))) & ">";
   end Short_Image;

   -----------------
   -- Sorted_Envs --
   -----------------

   --  Those ordered maps are used to have a stable representation of internal
   --  lexical environments, which is not the case with hashed maps.

   function "<" (L, R : Symbol_Type) return Boolean
   is
     (L.all < R.all);

   package Sorted_Envs is new Ada.Containers.Ordered_Maps
     (Symbol_Type,
      Element_Type    => AST_Envs.Internal_Map_Element_Vectors.Vector,
      "<"             => "<",
      "="             => AST_Envs.Internal_Map_Element_Vectors."=");

   -------------------
   -- To_Sorted_Env --
   -------------------

   function To_Sorted_Env (Env : Internal_Envs.Map) return Sorted_Envs.Map is
      Ret_Env : Sorted_Envs.Map;
      use Internal_Envs;
   begin
      for El in Env.Iterate loop
         Ret_Env.Include (Key (El), Element (El));
      end loop;
      return Ret_Env;
   end To_Sorted_Env;

   ----------------
   -- Get_Env_Id --
   ----------------

   function Get_Env_Id
     (E : Lexical_Env; State : in out Dump_Lexical_Env_State) return String
   is
      C        : Address_To_Id_Maps.Cursor;
      Inserted : Boolean;
   begin
      if E = null then
         return "$null";

      elsif E = State.Root_Env then
         --  Insert root env with a special Id so that we only print it once
         State.Env_Ids.Insert (E, -1, C, Inserted);
         return "$root";
      end if;

      State.Env_Ids.Insert (E, State.Next_Id, C, Inserted);
      if Inserted then
         State.Next_Id := State.Next_Id + 1;
      end if;

      return '@' & Stripped_Image (Address_To_Id_Maps.Element (C));
   end Get_Env_Id;

   ----------
   -- Dump --
   ----------

   procedure Dump_One_Lexical_Env
     (Self           : AST_Envs.Lexical_Env;
      Env_Id         : String := "";
      Parent_Env_Id  : String := "";
      Dump_Addresses : Boolean := False;
      Dump_Content   : Boolean := True)
   is
      use Sorted_Envs;

      function Short_Image
        (N : access ${root_node_value_type}'Class) return String
      is (if N = null then "<null>" else Image (N.Short_Image));
      -- TODO??? This is slightly hackish, because we're converting a wide
      -- string back to string. But since we're using this solely for
      -- test/debug purposes, it should not matter. Still, would be good to
      -- have Text_Type everywhere at some point.

      function Image (El : Internal_Map_Element) return String is
        (Short_Image (El.Element));

      function Image is new AST_Envs.Internal_Map_Element_Vectors.Image
        (Image);

      First_Arg : Boolean := True;

      procedure New_Arg is
      begin
         if First_Arg then
            First_Arg := False;
         else
            Put (", ");
         end if;
      end New_Arg;

      ---------------------
      -- Dump_Referenced --
      ---------------------

      procedure Dump_Referenced
        (Name : String; Refs : AST_Envs.Referenced_Envs_Vectors.Vector)
      is
         Is_First : Boolean := True;
      begin
         for R of Refs loop
            declare
               Env : Lexical_Env := Get_Env (R.Getter);
            begin
               if Env /= Empty_Env then
                  if Is_First then
                     Put_Line ("    " & Name & ":");
                     Is_First := False;
                  end if;
                  Put ("      ");
                  if R.Getter.Dynamic then
                     Put (Short_Image (R.Getter.Node) & ": ");
                  end if;

                  Dump_One_Lexical_Env (Self           => Env,
                                        Dump_Addresses => Dump_Addresses,
                                        Dump_Content   => False);
                  New_Line;
                  Dec_Ref (Env);
               end if;
            end;
         end loop;
      end Dump_Referenced;

   begin
      if Env_Id'Length /= 0 then
         Put (Env_Id & " = ");
      end if;
      Put ("LexEnv(");
      if Self = Empty_Env then
         New_Arg;
         Put ("Empty");
      end if;
      if Self.Ref_Count /= AST_Envs.No_Refcount then
         New_Arg;
         Put ("Synthetic");
      end if;
      if Parent_Env_Id'Length > 0 then
         New_Arg;
         Put ("Parent=" & (if Self.Parent /= AST_Envs.No_Env_Getter
                           then Parent_Env_Id else "null"));
      end if;
      if Self.Node /= null then
         New_Arg;
         Put ("Node=" & Image (Self.Node.Short_Image));
      end if;
      if Dump_Addresses then
         New_Arg;
         Put ("0x" & System.Address_Image (Self.all'Address));
      end if;
      Put (")");
      if not Dump_Content then
         return;
      end if;
      Put_Line (":");

      Dump_Referenced ("Referenced", Self.Referenced_Envs);

      if Self.Env = null then
         Put_Line ("    <null>");
      elsif Self.Env.Is_Empty then
         Put_Line ("    <empty>");
      else
         for El in To_Sorted_Env (Self.Env.all).Iterate loop
            Put ("    ");
            Put_Line (Langkit_Support.Text.Image (Key (El).all) & ": "
                 & Image (Element (El)));
         end loop;
      end if;
      New_Line;
   end Dump_One_Lexical_Env;

   ----------------------
   -- Dump_Lexical_Env --
   ----------------------

   procedure Dump_Lexical_Env
     (Node     : access ${root_node_value_type}'Class;
      Root_Env : AST_Envs.Lexical_Env)
   is
      State : Dump_Lexical_Env_State := (Root_Env => Root_Env, others => <>);

      --------------------------
      -- Explore_Parent_Chain --
      --------------------------

      procedure Explore_Parent_Chain (Env : Lexical_Env) is
      begin
         if Env /= null then
            Dump_One_Lexical_Env
              (Env, Get_Env_Id (Env, State),
               Get_Env_Id (AST_Envs.Get_Env (Env.Parent), State));
            Explore_Parent_Chain (AST_Envs.Get_Env (Env.Parent));
         end if;
      end Explore_Parent_Chain;

      --------------
      -- Internal --
      --------------

      procedure Internal (Current : ${root_node_type_name}) is
         Explore_Parent : Boolean := False;
         Env, Parent    : Lexical_Env;
      begin
         if Current = null then
            return;
         end if;

         --  We only dump environments that we haven't dumped before. This way
         --  we'll only dump environments at the site of their creation, and
         --  not in any subsequent link. We use the Env_Ids map to check which
         --  envs we have already seen or not.
         if not State.Env_Ids.Contains (Current.Self_Env) then
            Env := Current.Self_Env;
            Parent := Ast_Envs.Get_Env (Env.Parent);
            Explore_Parent := not State.Env_Ids.Contains (Parent);

            Dump_One_Lexical_Env
              (Env, Get_Env_Id (Env, State), Get_Env_Id (Parent, State));

            if Explore_Parent then
               Explore_Parent_Chain (Parent);
            end if;
         end if;

         for Child of ${root_node_array.api_name}'(Children (Current)) loop
            Internal (Child);
         end loop;
      end Internal;
      --  This procedure implements the main recursive logic of dumping the
      --  environments.
   begin
      Internal (${root_node_type_name} (Node));
   end Dump_Lexical_Env;

   -----------------------------------
   -- Dump_Lexical_Env_Parent_Chain --
   -----------------------------------

   procedure Dump_Lexical_Env_Parent_Chain (Env : AST_Envs.Lexical_Env) is
      Id : Positive := 1;
      E  : Lexical_Env := Env;
   begin
      if E = null then
         Put_Line ("<null>");
      end if;

      while E /= null loop
         declare
            Id_Str : constant String := '@' & Stripped_Image (Id);
         begin
            if E = null then
               Put_Line (Id_Str & " = <null>");
            else
               Dump_One_Lexical_Env
                 (Self           => E,
                  Env_Id         => Id_Str,
                  Parent_Env_Id  => '@' & Stripped_Image (Id + 1),
                  Dump_Addresses => True);
            end if;
         end;
         Id := Id + 1;
         E := AST_Envs.Get_Env (E.Parent);
      end loop;
   end Dump_Lexical_Env_Parent_Chain;

   -------------
   -- Parents --
   -------------

   function Parents
     (Node         : access ${root_node_value_type}'Class;
      Include_Self : Boolean := True)
      return ${root_node_array.name}
   is
      Count : Natural := 0;
      Start : ${root_node_type_name} :=
        ${root_node_type_name} (if Include_Self then Node else Node.Parent);
      Cur   : ${root_node_type_name} := Start;
   begin
      while Cur /= null loop
         Count := Count + 1;
         Cur := Cur.Parent;
      end loop;

      declare
         Result : constant ${root_node_array.name} := Create (Count);
      begin
         Cur := Start;
         for I in Result.Items'Range loop
            Result.Items (I) := Cur;
            Cur := Cur.Parent;
         end loop;
         return Result;
      end;
   end Parents;

   -----------------------
   -- First_Child_Index --
   -----------------------

   function First_Child_Index
     (Node : access ${root_node_value_type}'Class) return Natural
   is (1);

   ----------------------
   -- Last_Child_Index --
   ----------------------

   function Last_Child_Index
     (Node : access ${root_node_value_type}'Class) return Natural
   is (Node.Child_Count);

   ------------
   -- Parent --
   ------------

   function Parent
     (Node : access ${root_node_value_type}'Class) return ${root_node_type_name}
   is
   begin
      return Node.Parent;
   end Parent;

   ------------------
   -- Stored_Token --
   ------------------

   function Stored_Token
     (Node  : access ${root_node_value_type}'Class;
      Token : Token_Type)
      return Token_Index
   is
   begin
      if Node.Unit.TDH'Access /= Token.TDH then
         raise Property_Error with
           ("Cannot associate a token and a node from different analysis"
            & " units");
      elsif Token.Trivia /= No_Token_Index then
         raise Property_Error with
           ("A node cannot hold trivia");
      end if;

      return Token.Token;
   end Stored_Token;

   --------------
   -- Is_Ghost --
   --------------

   function Is_Ghost
     (Node : access ${root_node_value_type}'Class) return Boolean
   is (Node.Token_End_Index = No_Token_Index);

   ------------------
   -- Is_Synthetic --
   ------------------

   function Is_Synthetic
     (Node : access ${root_node_value_type}'Class) return Boolean
   is (Node.Token_Start_Index = No_Token_Index);

   -----------------
   -- Token_Start --
   -----------------

   function Token_Start
     (Node : access ${root_node_value_type}'Class)
      return Token_Type
   is (Node.Token (Node.Token_Start_Index));

   ---------------
   -- Token_End --
   ---------------

   function Token_End
     (Node : access ${root_node_value_type}'Class)
      return Token_Type
   is
     (if Node.Token_End_Index = No_Token_Index
      then Node.Token_Start
      else Node.Token (Node.Token_End_Index));

   -----------
   -- Token --
   -----------

   function Token
     (Node  : access ${root_node_value_type}'Class;
      Index : Token_Index) return Token_Type
   is
     (if Index = No_Token_Index
      then No_Token
      else (TDH    => Token_Data (Node.Unit),
            Token  => Index,
            Trivia => No_Token_Index));

   -------------
   -- Is_Null --
   -------------

   function Is_Null
     (Node : access ${root_node_value_type}'Class) return Boolean
   is (Node = null);

   -----------------
   -- Child_Index --
   -----------------

   function Child_Index
     (Node : access ${root_node_value_type}'Class)
      return Natural
   is
      N : ${root_node_type_name} := null;
   begin
      if Node.Parent = null then
         raise Property_Error with
            "Trying to get the child index of a root node";
      end if;

      for I in Node.Parent.First_Child_Index .. Node.Parent.Last_Child_Index
      loop
         N := Child (Node.Parent, I);
         if N = Node then
            return I - 1;
         end if;
      end loop;

      --  If we reach this point, then Node isn't a Child of Node.Parent. This
      --  is not supposed to happen.
      raise Program_Error;
   end Child_Index;

   ----------------------
   -- Previous_Sibling --
   ----------------------

   function Previous_Sibling
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_type_name}
   is
      N : constant Positive := Child_Index (Node) + 1;
   begin
      return (if N = 1
              then null
              else Node.Parent.Child (N - 1));
   end Previous_Sibling;

   ------------------
   -- Next_Sibling --
   ------------------

   function Next_Sibling
     (Node : access ${root_node_value_type}'Class)
     return ${root_node_type_name}
   is
      N : constant Positive := Child_Index (Node) + 1;
   begin
      --  If Node is the last sibling, then Child will return null
      return Node.Parent.Child (N + 1);
   end Next_Sibling;

   ## Env metadata's body

   ${struct_types.body(T.env_md)}

   -------------
   -- Combine --
   -------------

   function Combine
     (L, R : ${T.env_md.name}) return ${T.env_md.name}
   is
      % if not T.env_md.get_fields():
      pragma Unreferenced (L, R);
      % endif
      Ret : ${T.env_md.name} := ${T.env_md.nullexpr};
   begin
      % for field in T.env_md.get_fields():
         % if field.type.is_bool_type:
         Ret.${field.name} := L.${field.name} or R.${field.name};
         % else:
         if L.${field.name} = ${field.type.nullexpr} then
            Ret.${field.name} := R.${field.name};
         elsif R.${field.name} = ${field.type.nullexpr} then
            Ret.${field.name} := L.${field.name};
         else
            raise Property_Error with "Wrong combine for metadata field";
         end if;
         % endif

      % endfor
      return Ret;
   end Combine;

   ---------
   -- Get --
   ---------

   function Get
     (A     : AST_Envs.Entity_Array;
      Index : Integer)
      return Entity
   is
      function Length (A : AST_Envs.Entity_Array) return Natural
      is (A'Length);

      function Get
        (A     : AST_Envs.Entity_Array;
         Index : Integer)
         return Entity
      is (A (Index + 1)); --  A is 1-based but Index is 0-based

      function Relative_Get is new Langkit_Support.Relative_Get
        (Item_Type     => Entity,
         Sequence_Type => AST_Envs.Entity_Array,
         Length        => Length,
         Get           => Get);
      Result : Entity;
   begin
      if Relative_Get (A, Index, Result) then
         return Result;
      else
         raise Property_Error with "out-of-bounds array access";
      end if;
   end Get;

   -----------
   -- Group --
   -----------

   function Group
     (Envs : ${T.LexicalEnv.array.name})
      return ${T.LexicalEnv.name}
   is (Group (Envs.Items));

   % for astnode in ctx.astnode_types:
       ${astnode_types.body_decl(astnode)}
   % endfor

   ------------------
   -- Children_Env --
   ------------------

   function Children_Env
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Lexical_Env
   is (Rebind_Env (Node.Self_Env, E_Info));

   --------------
   -- Node_Env --
   --------------

   function Node_Env
     (Node   : access ${root_node_value_type};
      E_Info : Entity_Info := No_Entity_Info) return AST_Envs.Lexical_Env
   is (Rebind_Env (Node.Self_Env, E_Info));

   ------------
   -- Parent --
   ------------

   function Parent
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Entity is
   begin
      --  TODO: shed entity information as appropriate
      return (Node.Parent, E_Info);
   end Parent;

   -------------
   -- Parents --
   -------------

   function Parents
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Entity_Array_Access
   is
      Bare_Parents : ${root_node_array.name} := Node.Parents;
      Result       : Entity_Array_Access := Create (Bare_Parents.N);
   begin
      --  TODO: shed entity information as appropriate
      for I in Bare_Parents.Items'Range loop
         Result.Items (I) := (Bare_Parents.Items (I), E_Info);
      end loop;
      Dec_Ref (Bare_Parents);
      return Result;
   end Parents;

   --------------
   -- Children --
   --------------

   function Children
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Entity_Array_Access
   is
      Bare_Children : ${root_node_array.name} := Node.Children;
      Result        : Entity_Array_Access := Create (Bare_Children.N);
   begin
      --  TODO: shed entity information as appropriate
      for I in Bare_Children.Items'Range loop
         Result.Items (I) := (Bare_Children.Items (I), E_Info);
      end loop;
      Dec_Ref (Bare_Children);
      return Result;
   end Children;

   ----------------------
   -- Previous_Sibling --
   ----------------------

   function Previous_Sibling
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Entity is
   begin
      return (Node.Previous_Sibling, E_Info);
   end Previous_Sibling;

   ------------------
   -- Next_Sibling --
   ------------------

   function Next_Sibling
     (Node   : access ${root_node_value_type}'Class;
      E_Info : Entity_Info := No_Entity_Info) return Entity is
   begin
      return (Node.Next_Sibling, E_Info);
   end Next_Sibling;

   ## Generate the bodies of the root grammar class properties
   % for prop in T.root_node.get_properties(include_inherited=False):
   ${prop.prop_def}
   % endfor

   ## Generate bodies of untyped wrappers
   % for prop in T.root_node.get_properties( \
      include_inherited=False, \
      predicate=lambda f: f.requires_untyped_wrapper \
   ):
   ${prop.untyped_wrapper_def}
   % endfor

   --------------------------------
   -- Assign_Names_To_Logic_Vars --
   --------------------------------

   procedure Assign_Names_To_Logic_Vars
    (Node : access ${root_node_value_type}'Class) is
   begin
      % for f in T.root_node.get_fields( \
           include_inherited=False, \
           predicate=lambda f: f.type.is_logic_var_type \
      ):
         Node.${f.name}.Dbg_Name :=
            new String'(Image (Node.Short_Image) & ".${f.name}");
      % endfor
      Assign_Names_To_Logic_Vars_Impl (Node);
      for Child of ${root_node_array.api_name}'(Children (Node)) loop
         if Child /= null then
            Assign_Names_To_Logic_Vars (Child);
         end if;
      end loop;
   end Assign_Names_To_Logic_Vars;

   -----------
   -- Image --
   -----------

   function Image (Ent : ${T.entity.name}) return Text_Type is
   begin
      if Ent.El /= null then
         declare
            Node_Image : constant Text_Type := Ent.El.Short_Image;
         begin
            return
            (if Ent.Info.Rebindings /= null
             then "<| "
             & Node_Image (Node_Image'First + 1 .. Node_Image'Last -1) & " "
             & AST_Envs.Image (Ent.Info.Rebindings) & " |>"
             else Node_Image);
         end;
      else
         return "None";
      end if;
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Ent : ${T.entity.name}) return String is
      Result : constant Text_Type := Image (Ent);
   begin
      return Image (Result);
   end Image;

   ---------------
   -- Can_Reach --
   ---------------

   function Can_Reach (El, From : ${root_node_type_name}) return Boolean is
   begin
      --  Since this function is only used to implement sequential semantics in
      --  envs, we consider that elements coming from different units are
      --  always visible for each other, and let the user implement language
      --  specific visibility rules in the DSL.
      if El = null or else From = null or else El.Unit /= From.Unit then
         return True;
      end if;

       return Compare
         (Start_Sloc (Sloc_Range (El)),
          Start_Sloc (Sloc_Range (From))) = After;
   end Can_Reach;

   ------------
   -- Create --
   ------------

   function Create
      (El : ${root_node_type_name}; Info : Entity_Info)
       return Entity is
    begin
      return (El => El, Info => Info);
    end Create;

   procedure Register_Destroyable is new Register_Destroyable_Gen
     (AST_Envs.Lexical_Env_Type, AST_Envs.Lexical_Env, AST_Envs.Destroy);

   pragma Warnings (Off, "referenced");
   procedure Register_Destroyable
     (Unit : Analysis_Unit; Node : ${root_node_type_name});
   --  Helper for synthetized nodes. We cannot used the generic
   --  Register_Destroyable because the root AST node is an abstract types, so
   --  this is implemented using the untyped (using System.Address)
   --  implementation helper.
   pragma Warnings (Off, "referenced");

   procedure Destroy_Synthetic_Node (Node : in out ${root_node_type_name});
   --  Helper for the Register_Destroyable above

   function Get_Lex_Env_Data
     (Node : access ${root_node_value_type}'Class) return Lex_Env_Data
   is (${ada_lib_name}.Analysis.Get_Lex_Env_Data (Node.Unit));

   ---------------
   -- Get_Child --
   ---------------

   overriding procedure Get_Child
     (Node            : access ${generic_list_value_type};
      Index           : Positive;
      Index_In_Bounds : out Boolean;
      Result          : out ${root_node_type_name}) is
   begin
      if Index > Node.Count then
         Index_In_Bounds := False;
      else
         Index_In_Bounds := True;
         Result := Node.Nodes (Index);
      end if;
   end Get_Child;

   -----------
   -- Print --
   -----------

   overriding procedure Print
     (Node : access ${generic_list_value_type}; Line_Prefix : String := "")
   is
      Class_Wide_Node : constant ${root_node_type_name} :=
         ${root_node_type_name} (Node);
   begin
      Put
        (Line_Prefix & Class_Wide_Node.Kind_Name
         & "[" & Image (Node.Sloc_Range) & "]");
      if Node.Count = 0 then
         Put_Line (": <empty list>");
         return;
      end if;

      New_Line;
      for Child of Node.Nodes (1 .. Node.Count) loop
         if Child /= null then
            Child.Print (Line_Prefix & "|  ");
         end if;
      end loop;
   end Print;

   % for struct_type in no_builtins(ctx.struct_types):
   ${struct_types.body(struct_type)}
   % endfor

   ${astnode_types.logic_helpers()}

   % for astnode in no_builtins(ctx.astnode_types):
     % if not astnode.is_list_type:
       ${astnode_types.body(astnode)}
     % endif
   % endfor

   % for astnode in ctx.astnode_types:
      % if astnode.is_root_list_type:
         ${list_types.body(astnode.element_type)}
      % elif astnode.is_list_type:
         ${astnode_types.body(astnode)}
      % endif
   % endfor

   --------------------------
   -- Register_Destroyable --
   --------------------------

   procedure Register_Destroyable
     (Unit : Analysis_Unit; Node : ${root_node_type_name})
   is
      procedure Helper is new Register_Destroyable_Gen
        (${root_node_value_type}'Class,
         ${root_node_type_name},
         Destroy_Synthetic_Node);
   begin
      Helper (Unit, Node);
   end Register_Destroyable;

   ----------------------------
   -- Destroy_Synthetic_Node --
   ----------------------------

   procedure Destroy_Synthetic_Node (Node : in out ${root_node_type_name}) is
      procedure Free is new Ada.Unchecked_Deallocation
        (${root_node_value_type}'Class, ${root_node_type_name});
   begin
      --  Don't call Node.Destroy, as Node's children may be gone already: they
      --  have their own destructor and there is no specified order for the
      --  call of these destructors.
      Node.Free_Extensions;
      Node.Reset_Caches;

      Free (Node);
   end Destroy_Synthetic_Node;

   -----------
   -- Image --
   -----------

   function Image (Value : Boolean) return String
   is (if Value then "True" else "False");


   Kind_Names : array (${root_node_kind_name}) of Unbounded_String :=
     (${", \n".join(cls.ada_kind_name()
                    + " => To_Unbounded_String (\""
                    + cls.repr_name() + "\")"
                    for cls in ctx.astnode_types if not cls.abstract)});

   ---------------
   -- Kind_Name --
   ---------------

   function Kind_Name
     (Node : access ${root_node_value_type}'Class) return String
   is
   begin
      return To_String (Kind_Names (Node.Kind));
   end Kind_Name;

   Kind_To_Counts : array (${root_node_kind_name}) of Integer :=
     (${", \n".join(cls.ada_kind_name()
                    + " => {}".format(
                        len(cls.get_parse_fields(lambda f: f.type.is_ast_node))
                        if not cls.is_list_type
                        else -1
                    )
                    for cls in ctx.astnode_types if not cls.abstract)});

   -----------------
   -- Child_Count --
   -----------------

   function Child_Count
     (Node : access ${root_node_value_type}'Class) return Natural
   is
      C : Integer := Kind_To_Counts (Node.Kind);
   begin
      if C = -1 then
         return ${generic_list_type_name} (Node).Count;
      else
         return C;
      end if;
   end Child_Count;

   ------------------
   -- Reset_Caches --
   ------------------

   procedure Reset_Caches (Node : access ${root_node_value_type}'Class) is
      K : ${root_node_kind_name} := Node.Kind;
   begin
   case K is
   % for cls in ctx.astnode_types:
      % if not cls.abstract:
         <%
            memo_props = cls.get_memoized_properties(include_inherited=True)
            logic_vars = [fld for fld in cls.get_user_fields()
                          if fld.type.is_logic_var_type]
         %>
         % if memo_props or logic_vars:
            when ${cls.ada_kind_name()} =>
               declare
                  N : ${cls.name} := ${cls.name} (Node);
               begin
                  % if memo_props:
                     % for p in memo_props:
                        % if p.type.is_refcounted:
                           if N.${p.memoization_state_field_name} = Computed
                           then
                              Dec_Ref (N.${p.memoization_value_field_name});
                           end if;
                        % endif
                        N.${p.memoization_state_field_name} := Not_Computed;
                     % endfor
                  % endif

                  % if logic_vars:
                     % for field in logic_vars:
                        --  TODO??? Fix Adalog so that Destroy resets the
                        --  value it stores.
                        N.${field.name}.Value := No_Entity;
                        Eq_Node.Refs.Reset (N.${field.name});
                        Eq_Node.Refs.Destroy (N.${field.name});
                     % endfor
                  % endif
               end;
         % endif
      % endif
   % endfor
   when others => null;
   end case;
   end Reset_Caches;

   -----------------------
   -- Entity converters --
   -----------------------

   % for e in ctx.entity_types:
      function As_${e.el_type.name}
        (Node : ${root_entity.api_name}'Class) return ${e.api_name} is
      begin
         if Node.Node = null then
            return No_${e.api_name};
         elsif Node.Node.all in ${e.el_type.value_type_name()}'Class then
            return (Node => Node.Node, E_Info => Node.E_Info);
         else
            raise Constraint_Error with "Invalid type conversion";
         end if;
      end;
   % endfor

   -----------------------
   -- Entity primitives --
   -----------------------

   ----------
   -- Kind --
   ----------

   function Kind
     (Node : ${root_entity.api_name}'Class) return ${root_node_kind_name} is
   begin
      return Node.Node.Kind;
   end Kind;

   ---------------
   -- Kind_Name --
   ---------------

   function Kind_Name (Node : ${root_entity.api_name}'Class) return String is
   begin
      return Node.Node.Kind_Name;
   end Kind_Name;

   --------------
   -- Is_Ghost --
   --------------

   function Is_Ghost (Node : ${root_entity.api_name}'Class) return Boolean is
   begin
      return Node.Node.Is_Ghost;
   end Is_Ghost;

   --------------
   -- Get_Unit --
   --------------

   function Get_Unit
     (Node : ${root_entity.api_name}'Class) return Analysis_Unit is
   begin
      return Node.Node.Get_Unit;
   end Get_Unit;

   % for e in ctx.entity_types:
      % for p in e.el_type.get_properties( \
         include_inherited=False, \
         predicate=lambda p: p.is_public and not p.overriding \
      ):
         ${public_properties.body(p)}
      % endfor
   % endfor

   -----------------
   -- Child_Count --
   -----------------

   function Child_Count
     (Node : ${root_entity.api_name}'Class) return Natural is begin
      return Node.Node.Child_Count;
   end Child_Count;

   -----------------------
   -- First_Child_Index --
   -----------------------

   function First_Child_Index
     (Node : ${root_entity.api_name}'Class) return Natural is
   begin
      return Node.Node.First_Child_Index;
   end First_Child_Index;

   ----------------------
   -- Last_Child_Index --
   ----------------------

   function Last_Child_Index
     (Node : ${root_entity.api_name}'Class) return Natural is
   begin
      return Node.Node.Last_Child_Index;
   end Last_Child_Index;

   ---------------
   -- Get_Child --
   ---------------

   procedure Get_Child
     (Node            : ${root_entity.api_name};
      Index           : Positive;
      Index_In_Bounds : out Boolean;
      Result          : out ${root_entity.api_name})
   is
      N : ${root_node_type_name};
   begin
      Node.Node.Get_Child (Index, Index_In_Bounds, N);
      Result := (N, Node.E_Info);
   end Get_Child;

   -----------
   -- Child --
   -----------

   function Child
     (Node  : ${root_entity.api_name}'Class;
      Index : Positive) return ${root_entity.api_name}
   is
   begin
      return (Node.Node.Child (Index), Node.E_Info);
   end Child;

   ----------------
   -- Sloc_Range --
   ----------------

   function Sloc_Range
     (Node : ${root_entity.api_name}'Class;
      Snap : Boolean := False) return Source_Location_Range is
   begin
      return Node.Node.Sloc_Range;
   end Sloc_Range;

   -------------
   -- Compare --
   -------------

   function Compare
     (Node : ${root_entity.api_name}'Class;
      Sloc : Source_Location;
      Snap : Boolean := False) return Relative_Position is
   begin
      return Node.Node.Compare (Sloc, Snap);
   end Compare;

   ------------
   -- Lookup --
   ------------

   function Lookup
     (Node : ${root_entity.api_name}'Class;
      Sloc : Source_Location;
      Snap : Boolean := False) return ${root_entity.api_name} is
   begin
      return (Node.Node.Lookup (Sloc, Snap), No_Entity_Info);
   end Lookup;

   ----------
   -- Text --
   ----------

   function Text (Node : ${root_entity.api_name}'Class) return Text_Type is
   begin
      return Node.Node.Text;
   end Text;

   --  TODO??? Bind Children_With_Trivia (changing the Node type in
   --  Child_Record).

   -----------------
   -- Token_Range --
   -----------------

   function Token_Range
     (Node : ${root_entity.api_name}'Class)
      return Token_Iterator is
   begin
      return Node.Node.Token_Range;
   end Token_Range;

   --------
   -- PP --
   --------

   function PP (Node : ${root_entity.api_name}'Class) return String is
   begin
      return Node.Node.PP;
   end PP;

   -----------
   -- Print --
   -----------

   procedure Print
     (Node        : ${root_entity.api_name}'Class;
      Line_Prefix : String := "") is
   begin
      Node.Node.Print (Line_Prefix);
   end Print;

   ---------------
   -- PP_Trivia --
   ---------------

   procedure PP_Trivia
     (Node        : ${root_entity.api_name}'Class;
      Line_Prefix : String := "") is
   begin
      Node.Node.PP_Trivia (Line_Prefix);
   end PP_Trivia;

   ----------------------
   -- Dump_Lexical_Env --
   ----------------------

   procedure Dump_Lexical_Env
     (Node     : ${root_entity.api_name}'Class;
      Root_Env : AST_Envs.Lexical_Env) is
   begin
      Node.Node.Dump_Lexical_Env (Root_Env);
   end Dump_Lexical_Env;

   --------------------------------
   -- Assign_Names_To_Logic_Vars --
   --------------------------------

   procedure Assign_Names_To_Logic_Vars (Node : ${root_entity.api_name}'Class)
   is
   begin
      Node.Node.Assign_Names_To_Logic_Vars;
   end Assign_Names_To_Logic_Vars;

   --------------
   -- Traverse --
   --------------

   function Traverse
     (Node  : ${root_entity.api_name}'Class;
      Visit : access function (Node : ${root_entity.api_name}'Class)
              return Visit_Status)
     return Visit_Status
   is
      E_Info : constant Entity_Info := Node.E_Info;

      -------------
      -- Wrapper --
      -------------

      function Wrapper
        (Node : access ${root_node_value_type}'Class) return Visit_Status
      is
         Public_Node : constant ${root_entity.api_name} :=
           (${root_node_type_name} (Node), E_Info);
      begin
         return Visit (Public_Node);
      end Wrapper;

   begin
      return Node.Node.Traverse (Wrapper'Access);
   end Traverse;

   --------------
   -- Traverse --
   --------------

   procedure Traverse
     (Node  : ${root_entity.api_name}'Class;
      Visit : access function (Node : ${root_entity.api_name}'Class)
                               return Visit_Status)
   is
      Result_Status : Visit_Status;
      pragma Unreferenced (Result_Status);
   begin
      Result_Status := Traverse (Node, Visit);
   end Traverse;

   -------------------------------
   -- Public_Traverse_With_Data --
   -------------------------------

   function Public_Traverse_With_Data
     (Node  : ${root_entity.api_name}'Class;
      Visit : access function (Node : ${root_entity.api_name}'Class;
                               Data : in out Data_type)
                               return Visit_Status;
      Data  : in out Data_Type)
      return Visit_Status
   is
      E_Info : constant Entity_Info := Node.E_Info;

      ------------
      -- Helper --
      ------------

      function Helper
        (Node : access ${root_node_value_type}'Class) return Visit_Status
      is
         Public_Node : constant ${root_entity.api_name} :=
           (${root_node_type_name} (Node), E_Info);
      begin
         return Visit (Public_Node, Data);
      end Helper;

      Saved_Data : Data_Type;
      Result     : Visit_Status;

   begin
      if Reset_After_Traversal then
         Saved_Data := Data;
      end if;
      Result := Node.Node.Traverse (Helper'Access);
      if Reset_After_Traversal then
         Data := Saved_Data;
      end if;
      return Result;
   end Public_Traverse_With_Data;

   -----------------
   -- Child_Index --
   -----------------

   function Child_Index (Node : ${root_entity.api_name}'Class) return Natural
   is
   begin
      return Node.Node.Child_Index;
   end Child_Index;

end ${ada_lib_name}.Analysis;
