------------------------------------------------------------------------------
--                                                                          --
--                                 Langkit                                  --
--                                                                          --
--                        Copyright (C) 2019, AdaCore                       --
--                                                                          --
-- Langkit is free software; you can redistribute it and/or modify it under --
-- terms of the  GNU General Public License  as published by the Free Soft- --
-- ware Foundation;  either version 3,  or (at your option)  any later ver- --
-- sion.   This software  is distributed in the hope that it will be useful --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY  or  FITNESS  FOR A PARTICULAR PURPOSE.                         --
--                                                                          --
-- As a special  exception  under  Section 7  of  GPL  version 3,  you are  --
-- granted additional  permissions described in the  GCC  Runtime  Library  --
-- Exception, version 3.1, as published by the Free Software Foundation.    --
--                                                                          --
-- You should have received a copy of the GNU General Public License and a  --
-- copy of the GCC Runtime Library Exception along with this program;  see  --
-- the files COPYING3 and COPYING.RUNTIME respectively.  If not, see        --
-- <http://www.gnu.org/licenses/>.                                          --
------------------------------------------------------------------------------

package body Langkit_Support.Adalog.Solver is

   Global_Kind : Solver_Kind := Symbolic;

   --------------
   -- Set_Kind --
   --------------

   procedure Set_Kind (Kind : Solver_Kind) is
   begin
      Global_Kind := Kind;
   end Set_Kind;

   -------------
   -- Inc_Ref --
   -------------

   procedure Inc_Ref (Self : Relation) is
   begin
      case Self.Kind is
         when Symbolic => Sym_Solve.Inc_Ref (Self.Symbolic_Relation);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Inc_Ref;

   -------------
   -- Dec_Ref --
   -------------

   procedure Dec_Ref (Self : in out Relation) is
   begin
      case Self.Kind is
         when Symbolic => Sym_Solve.Dec_Ref (Self.Symbolic_Relation);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Dec_Ref;

   -----------
   -- Solve --
   -----------

   procedure Solve
     (Self              : Relation;
      Solution_Callback : access function return Boolean;
      Solve_Options     : Solve_Options_Type := Default_Options)
   is
   begin
      case Self.Kind is
         when Symbolic => Sym_Solve.Solve
              (Self.Symbolic_Relation, Solution_Callback, Solve_Options);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Solve;

   -----------
   -- Solve --
   -----------

   procedure Solve
     (Self              : Relation;
      Solution_Callback : access function
        (Vars : Logic_Var_Array) return Boolean;
      Solve_Options : Solve_Options_Type := Default_Options)
   is
   begin
      case Self.Kind is
         when Symbolic => Sym_Solve.Solve
              (Self.Symbolic_Relation, Solution_Callback, Solve_Options);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Solve;

   -----------------
   -- Solve_First --
   -----------------

   function Solve_First
     (Self : Relation; Solve_Options : Solve_Options_Type := Default_Options)
      return Boolean
   is
   begin
      case Self.Kind is
         when Symbolic =>
            return Sym_Solve.Solve_First
              (Self.Symbolic_Relation, Solve_Options);
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Solve_First;

   ----------------------
   -- Create_Predicate --
   ----------------------

   function Create_Predicate
     (Logic_Var    : Var;
      Pred         : Predicate_Type'Class;
      Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_Predicate (Logic_Var, Pred, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Predicate;

   ------------------------
   -- Create_N_Predicate --
   ------------------------

   function Create_N_Predicate
     (Logic_Vars   : Variable_Array;
      Pred         : N_Predicate_Type'Class;
      Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_N_Predicate (Logic_Vars, Pred, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_N_Predicate;

   -------------------
   -- Create_Assign --
   -------------------

   function Create_Assign
     (Logic_Var    : Var;
      Value        : Value_Type;
      Conv         : Converter_Type'Class := No_Converter;
      Eq           : Comparer_Type'Class  := No_Comparer;
      Debug_String : String_Access        := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_Assign
                 (Logic_Var, Value, Conv, Eq, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Assign;

   ------------------
   -- Create_Unify --
   ------------------

   function Create_Unify
     (From, To : Var; Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic, Sym_Solve.Create_Unify (From, To, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Unify;

   ----------------------
   -- Create_Propagate --
   ----------------------

   function Create_Propagate
     (From, To     : Var;
      Conv         : Converter_Type'Class := No_Converter;
      Eq           : Comparer_Type'Class := No_Comparer;
      Debug_String : String_Access       := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_Propagate (From, To, Conv, Eq, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Propagate;

   -------------------
   -- Create_Domain --
   -------------------

   function Create_Domain
     (Logic_Var    : Var; Domain : Value_Array;
      Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_Domain (Logic_Var, Domain, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Domain;

   ----------------
   -- Create_Any --
   ----------------

   function Create_Any
     (Relations : Relation_Array; Debug_String : String_Access := null)
      return Relation
   is
      Internal_Rels : Sym_Solve.Relation_Array (Relations'Range);
   begin
      for J in Relations'Range loop
         Internal_Rels (J) := Relations (J).Symbolic_Relation;
      end loop;

      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_Any (Internal_Rels, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_Any;

   ----------------
   -- Create_All --
   ----------------

   function Create_All
     (Relations : Relation_Array; Debug_String : String_Access := null)
      return Relation
   is
      Internal_Rels : Sym_Solve.Relation_Array (Relations'Range);
   begin
      for J in Relations'Range loop
         Internal_Rels (J) := Relations (J).Symbolic_Relation;
      end loop;

      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_All (Internal_Rels, Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_All;

   -----------------
   -- Create_True --
   -----------------

   function Create_True (Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_True (Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_True;

   ------------------
   -- Create_False --
   ------------------

   function Create_False (Debug_String : String_Access := null) return Relation
   is
   begin
      case Global_Kind is
         when Symbolic =>
            return Relation'
              (Symbolic,
               Sym_Solve.Create_False (Debug_String));
         when State_Machine =>
            return raise Program_Error with "Not implemented";
      end case;
   end Create_False;

   -----------
   -- Image --
   -----------

   function Image (Self : Relation; Level : Natural := 0) return String is
   begin
      case Self.Kind is
         when Symbolic =>
            return Sym_Solve.Image (Self.Symbolic_Relation, Level);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Image;

   --------------------
   -- Relation_Image --
   --------------------

   function Relation_Image (Self : Relation) return String is
   begin
      case Self.Kind is
         when Symbolic =>
            return Sym_Solve.Relation_Image (Self.Symbolic_Relation);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Relation_Image;

   --------------------
   -- Print_Relation --
   --------------------

   procedure Print_Relation (Self : Relation) is
   begin
      case Self.Kind is
         when Symbolic =>
            Sym_Solve.Print_Relation (Self.Symbolic_Relation);
         when State_Machine => raise Program_Error with "Not implemented";
      end case;
   end Print_Relation;

end Langkit_Support.Adalog.Solver;
