------------------------------------------------------------------------------
--                                                                          --
--                                 Langkit                                  --
--                                                                          --
--                     Copyright (C) 2014-2018, AdaCore                     --
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

with Ada.Environment_Variables;
with Ada.Text_IO; use Ada.Text_IO;

with Langkit_Support.Images;

package body Langkit_Support.Adalog.Generic_Main_Support is

   ------------
   -- Create --
   ------------

   function Create (Name : String) return Refs.Raw_Var is
   begin
      return R : constant Refs.Raw_Var := Refs.Create do
         R.Dbg_Name := new String'(Name);
         Variables.Append (R);
      end return;
   end Create;

   ---------
   -- "+" --
   ---------

   function "+" (R : Relation) return Relation is
   begin
      Relations.Append (R);
      return R;
   end "+";

   --------------------
   -- Safe_Get_Value --
   --------------------

   use Refs;
   use Refs.Raw_Logic_Var;

   function Safe_Get_Value (V : Refs.Raw_Var) return String is
     ((if Refs.Is_Defined (V)
       then Image (Refs.Get_Value (V))
       else "<undefined>"));

   ---------------
   -- Solve_All --
   ---------------

   procedure Solve_All (Rel : Relation; Show_Relation : Boolean := False) is
      function Solution_Callback (Vars : Var_Array) return Boolean;
      function Solution_Callback (Vars : Var_Array) return Boolean is

         function Image (L : Refs.Raw_Var) return String
         is (Refs.Image (L) & " = " & Safe_Get_Value (L));

         function Vars_Image is new Langkit_Support.Images.Array_Image
           (Raw_Var, Positive, Var_Array);
      begin
         Put_Line ("Solution: " & Vars_Image (Vars));
         return True;
      end Solution_Callback;
   begin
      if Show_Relation then
         Put_Line ("Solving relation:");
         Print_Relation (Rel);
      end if;
      Solve
        (Rel,
         Solution_Callback'Unrestricted_Access,
         (Cut_Dead_Branches => True));
   end Solve_All;

   ---------
   -- "-" --
   ---------

   function "-" (S : String) return String_Access is
   begin
      return Ret : constant String_Access := new String'(S) do
         --           Strings.Append (Ret);
         null;
      end return;
   end "-";

   --------------
   -- Finalize --
   --------------

   procedure Finalize is
      Used : Boolean := False;
   begin
      if not Destroyed then
         for R of Relations loop
            Used := True;
            Dec_Ref (R);
         end loop;

         for V of Variables loop
            Refs.Destroy (V.all);
            Refs.Free (V);
         end loop;

         for S of Strings loop
            Free (S);
         end loop;

         Relations := Relation_Vectors.Empty_Vector;
         Destroyed := True;

         if Used then
            Put_Line ("Done.");
         end if;
      end if;
   end Finalize;

   package Env renames Ada.Environment_Variables;
begin
   GNATCOLL.Traces.Parse_Config_File;
   if Env.Exists ("ADALOG_SOLVER_KIND") then
      if Env.Value ("ADALOG_SOLVER_KIND") = "SYM" then
         T_Solver.Set_Kind (Symbolic);
      elsif Env.Value ("ADALOG_SOLVER_KIND") = "SSM" then
         T_Solver.Set_Kind (State_Machine);
      else
         raise Program_Error
           with "Invalid value for env var ""ADALOG_SOLVER_KIND""";
      end if;
   end if;

end Langkit_Support.Adalog.Generic_Main_Support;