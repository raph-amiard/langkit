from __future__ import absolute_import, division, print_function

import os

from testsuite_support.base_driver import BaseDriver, catch_test_errors


class AdalogDriver(BaseDriver):
    TIMEOUT = 300

    @catch_test_errors
    def tear_up(self):
        super(AdalogDriver, self).tear_up()

    @catch_test_errors
    def run(self):
        self.create_project_file('p.gpr', ["adalog_main.adb"])
        main = "adalog_main.adb"
        with open(self.working_dir(main), "w") as f:
            f.write(
                """
                with Ada.Text_IO; use Ada.Text_IO;

                with Langkit_Support.Adalog;
                with Langkit_Support.Adalog.Main_Support;

                with Main;

                procedure Adalog_Main is
                    use Langkit_Support.Adalog.Main_Support.T_Solver;
                begin
                    Put_Line ("Solving with new solver");
                    Put_Line ("=======================");
                    Put_Line ("");
                    Main;

                    begin
                        Put_Line ("Solving with old solver");
                        Put_Line ("=======================");
                        Put_Line ("");
                        Set_Kind (State_Machine);
                        Main;
                    exception
                        when Langkit_Support.Adalog.Early_Binding_Error =>
                            Put_Line ("Resolution failed with Early_Binding_Error");
                    end;
                end Adalog_Main;
                """
            )
        self.gprbuild('p.gpr')
        argv = [self.program_path(main)]
        self.run_and_check(argv, for_coverage=True, memcheck=True)
