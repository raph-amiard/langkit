"""
Test that calling a memoized property on a null node triggers the expected
error.
"""

from __future__ import absolute_import, division, print_function

from langkit.dsl import ASTNode
from langkit.expressions import LazyField

from utils import build_and_run


class FooNode(ASTNode):
    four = LazyField(2 + 2, public=True)


class Example(FooNode):
    pass


build_and_run(lkt_file='expected_concrete_syntax.lkt', ada_main='main.adb')
print('Done')
