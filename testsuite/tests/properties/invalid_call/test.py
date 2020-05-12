from langkit.dsl import ASTNode, Int
from langkit.expressions import No, Property, Self

from utils import emit_and_print_errors


def run(name, expr):
    """
    Emit and print the errors we get for the below grammar with "expr" as
    a property in BarNode.
    """

    global FooNode

    print('== {} =='.format(name))

    class FooNode(ASTNode):
        pass

    class BarNode(FooNode):
        prop_2 = Property(lambda x=Int: x, public=True)
        prop = Property(expr, public=True)

    emit_and_print_errors(lkt_file='foo.lkt')
    print('')


run("Correct code", lambda: Self.prop_2(12))
run("Incorrect call code 1", lambda: Self.non_exisisting_prop(12))
run("Incorrect call code 2", lambda: Self.prop_2(12, 15))
run("Incorrect call code 3", lambda: Self.prop_2(No(FooNode)))
print('Done')
