from __future__ import absolute_import, division, print_function

import langkit.compiled_types as ct
from langkit.compiled_types import T
from langkit.language_api import AbstractAPISettings
from langkit.utils import dispatch_on_type


class PythonAPISettings(AbstractAPISettings):
    """Container for Python API generation settings."""

    name = 'python'

    def __init__(self, ctx, c_api_settings):
        self.context = ctx
        self.c_api_settings = c_api_settings

    @property
    def module_name(self):
        return self.context.lib_name.lower

    def get_enum_alternative(self, type_name, alt_name, suffix):
        return alt_name.upper

    def wrap_value(self, value, type, from_field_access=False):
        """
        Given an expression for a low-level value and the associated type,
        return an other expression that yields the corresponding high-level
        value.

        :param str value: Expression yielding a low-level value.
        :param ct.CompiledType type: Type corresponding to the "value"
            expression.
        :param bool from_field_access: True if "value" is a record field or
            array item access (False by default). This is a special case
            because of the way ctypes works.
        :rtype: str
        """
        value_suffix = '' if from_field_access else '.value'
        return dispatch_on_type(type, [
            (T.AnalysisUnitType, lambda _: 'AnalysisUnit._wrap({})'),
            (T.AnalysisUnitKind, lambda _: '_unit_kind_to_str[{}]'),
            (ct.ASTNodeType, lambda _: '{}._wrap_bare_node({{}})'.format(
                self.type_public_name(ct.T.root_node))),
            (ct.EntityType, lambda _: '{}._wrap({{}})'.format(
                self.type_public_name(ct.T.root_node))),
            (T.TokenType, lambda _: '{}'),
            (T.SymbolType, lambda _: '{}._wrap()'),
            (T.BoolType, lambda _: 'bool({{}}{})'.format(value_suffix)),
            (T.LongType, lambda _: '{{}}{}'.format(value_suffix)),
            (T.CharacterType, lambda _: 'unichr({{}}{})'.format(value_suffix)),
            (ct.ArrayType, lambda _: '{}._wrap({{}})'.format(
                self.array_wrapper(type)
            )),
            (ct.StructType, lambda _: '{}._wrap({{}})'.format(
                type.name.camel)),
            (T.EnvRebindingsType, lambda _: '{}'),
            (T.BigIntegerType, lambda _: '_big_integer._wrap({})'),
        ], exception=TypeError(
            'Unhandled field type in the python binding'
            ' (wrapping): {}'.format(type)
        )).format(value)

    def unwrap_value(self, value, type):
        """
        Given an expression for a high-level value and the associated type,
        return an other expression that yields the corresponding low-level
        value.

        :param str value: Expression yielding a high-level value.
        :param ct.CompiledType type: Type corresponding to the "value"
            expression.
        :rtype: str
        """
        return dispatch_on_type(type, [
            (T.AnalysisUnitType, lambda _: 'AnalysisUnit._unwrap({})'),
            (T.AnalysisUnitKind, lambda _: '_unwrap_unit_kind({})'),
            (ct.ASTNodeType, lambda _: '{}'),
            (ct.ASTNodeType, lambda _: '{}._node_c_value'),
            (ct.EntityType, lambda _: '{}._unwrap({{}})'.format(
                self.type_public_name(ct.T.root_node))),
            (T.BoolType, lambda _: 'bool({})'),
            (T.LongType, lambda _: 'int({})'),
            (T.CharacterType, lambda _: 'ord({})'),
            (ct.ArrayType, lambda cls: '{}._unwrap({{}})'.format(
                self.array_wrapper(cls)
            )),
            (ct.StructType, lambda _: '{}._unwrap({{}})'.format(
                type.name.camel
            )),
            (T.SymbolType, lambda _: '_text._unwrap({})'),
            (T.EnvRebindingsType, lambda _: '{}'),
            (T.BigIntegerType, lambda _: '_big_integer._unwrap({})'),
        ], exception=TypeError(
            'Unhandled field type in the python binding'
            ' (unwrapping): {}'.format(type)
        )).format(value)

    def c_type(self, type):
        """
        Return the name of the type to use in the C API for ``type``.

        :param CompiledType type: The type for which we want to get the C type
            name.
        :rtype: str
        """
        def ctype_type(name):
            return "ctypes.{}".format(name)

        def wrapped_type(name):
            return "_{}".format(name)

        return dispatch_on_type(type, [
            (T.BoolType, lambda _: ctype_type('c_uint8')),
            (T.LongType, lambda _: ctype_type('c_int')),
            (T.CharacterType, lambda _: ctype_type('c_uint32')),
            (T.EnvRebindingsType, lambda _: '_EnvRebindings_c_type'),
            (T.TokenType, lambda _: 'Token'),
            (T.SymbolType, lambda _: wrapped_type('text')),
            (T.AnalysisUnitType, lambda _: 'AnalysisUnit._c_type'),
            (T.AnalysisUnitKind, lambda _: ctype_type('c_uint')),
            (ct.ASTNodeType, lambda _: '{}._node_c_type'.format(
                self.type_public_name(ct.T.root_node))),
            (ct.ArrayType, lambda cls:
                '{}._c_type'.format(self.array_wrapper(cls))),
            (T.entity_info, lambda _: '_EntityInfo_c_type'),
            (ct.EntityType, lambda _: '_Entity_c_type'),
            (ct.StructType, lambda _:
                '{}._c_type'.format(type.name.camel)),
            (T.BigIntegerType, lambda _: '_big_integer'),
        ])

    def array_wrapper(self, array_type):
        return (ct.T.entity.array
                if array_type.element_type.is_entity_type else
                array_type).py_converter

    def type_public_name(self, type):
        """
        Python specific helper. Return the public API name for a given
        CompiledType instance.

        :param CompiledType type: The type for which we want to get the name.
        :rtype: str
        """
        return dispatch_on_type(type, [
            (T.BoolType, lambda _: 'bool'),
            (T.LongType, lambda _: 'int'),
            (T.CharacterType, lambda _: 'unicode'),
            (T.TokenType, lambda _: 'Token'),
            (T.SymbolType, lambda _: 'unicode'),
            (ct.ASTNodeType, lambda t: self.type_public_name(t.entity)),
            (ct.EntityType, lambda t: t.astnode.kwless_raw_name.camel),
            (T.AnalysisUnitType, lambda t: t.api_name),
            (ct.ArrayType, lambda _: 'list[{}]'.format(
                type.element_type.name.camel
            )),
            (ct.StructType, lambda _: type.name.camel),
            (T.AnalysisUnitKind, lambda _: 'str'),
            (T.BigIntegerType, lambda _: 'int'),
        ])
