--  This file contains the base class representing a logic relation. Equations
--  systems are basically a tree of Base_Relation subclasses instances.

package Langkit_Support.Adalog.Abstract_Relation is

   type Solving_Context is private;
   --  Information about the current relation being solved

   -------------------
   -- Base_Relation --
   -------------------

   type Solving_State is (Progress, No_Progress, Satisfied, Unsatisfied);

   subtype Finished_Solving_State is
      Solving_State range Satisfied ..  Unsatisfied;

   function "+" (B : Boolean) return Solving_State is
     (if B then Satisfied else Unsatisfied);

   type Base_Relation is abstract tagged record
      Ref_Count : Natural := 1;
   end record;

   type Relation is access all Base_Relation'Class;
   --  Since relations are trees, they're not manipulated by value, but instead
   --  via this class-wide access type.

   type Relation_Array is array (Positive range <>) of Relation;
   --  Some relations will need to keep/provide arrays of sub-relations

   Empty_Array : constant Relation_Array (1 .. 0) := (others => <>);

   --  Base type for a type implementing the relation interface. A relation has
   --  the following properties:
   --
   --  * It keeps references to zero or more sub-relations, relations that
   --    it will expand. For example, an AND relation will have two (or more)
   --    sub-relations.
   --
   --  * It keeps references to zero or more logical variables, that it will
   --    bind when solved.
   --
   --  * It can be solved, and that implies eventually solving sub relations,
   --    and eventually binding logic variables.
   --
   --  * It keeps the current state of solving, which is necessary since
   --    relation systems possibly have multiple solutions. This state can
   --    be reset via the Reset primitive.

   function Solve
     (Self    : in out Base_Relation'Class;
      Context : Solving_Context) return Solving_State;
   --  Try to solve the relation subtree::
   --
   --    * If some logic variables are cannot be bound whereas they are
   --      required to make progress, return Progress or No_Progress, depending
   --      on whether some progress could be made at all towards resolution.
   --
   --    * If resolution completes, return Satisfied when there exists a
   --      solution or Unsatisfied otherwise.

   function Solve_Impl
     (Self    : in out Base_Relation;
      Context : Solving_Context) return Solving_State is abstract;
   --  Solve function that must be implemented by relations

   procedure Reset (Self : in out Base_Relation) is abstract;
   --  Reset the state of the relation and all sub-relations

   procedure Cleanup (Self : in out Base_Relation) is abstract;
   --  Perform necessary cleanup before free, like releasing references and
   --  freeing owned resources. This needs to be implemented by Base_Relation
   --  implementers, and it will be called just before freeing Self in Dec_Ref.

   function Children (Self : Base_Relation) return Relation_Array
   is (Empty_Array);

   function Custom_Image (Self : Base_Relation) return String is abstract;
   --  Text to use in Print_Relation to represent this relation

   function Solve (Self : Relation) return Boolean;
   --  Function to solve the toplevel relation, used by Langkit

   procedure Print_Relation
     (Self             : Relation;
      Current_Relation : Relation := null;
      With_Colors      : Boolean := False);
   --  Debug helper: display a relation tree as human readable text on the
   --  standard output.
   --
   --  If With_Colors is true, output ANSII escape sequences to highlight the
   --  the given current relation in the tree.

   procedure Inc_Ref (Self : Relation);
   procedure Dec_Ref (Self : in out Relation);
   --  Reference counting primitives to be used by Langkit. A Dec_Ref call
   --  bringing the reference count to 0 will Destroy the referenced relation
   --  object and put the pointer to null, hence the in out mode.

private

   type Solving_Context is record
      Root_Relation : Relation;
      --  Root node for the current tree of relation being solved
   end record;

end Langkit_Support.Adalog.Abstract_Relation;
