[![Build Status](https://travis-ci.org/AdaCore/langkit.svg?branch=master
)](https://travis-ci.org/AdaCore/langkit)

Langkit
=======

Langkit (nickname for language kit) is a tool whose purpose is to make it easy
to create syntactic and semantic analysis engines. Write a language
specification in our Python DSL and Langkit will generate for you an Ada
library with bindings for the C and Python programming languages.

The generated library is meant to provide a basis to write tooling, including
tools working on potentially changing and incorrect code, such as IDEs.

The currently main Langkit user is
[Libadalang](https://github.com/AdaCore/libadalang), a high performance
semantic engine for the Ada programming language.

Dependencies
------------

To use Langkit:

* A Python 3.7+ intererpter. Python2 is no longer supported.
* The mako template system for Python (see `REQUIREMENTS.dev`).
* Clang-format.

Install
-------

There is no proper distribution for the langkit Python package, so just add the
top-level langkit directory to your `PYTHONPATH` in order to use it. Note that
this directory is self-contained, so you can copy it somewhere else.

Testing
-------

First, make sure the langkit package is available from the Python interpreter
(see Install).  Then, in order to run the testsuite, launch the following
command from the top-level directory:

    $ scripts/interactive_testsuite

This is just a wrapper script passing convenient options to the real testsuite
driver that is in `testsuite/testsuite.py`.

If you want to learn more about this test driver's options (for instance to run
tests under Valgrind), add a `-h` flag.

Documentation
-------------

The developer and user's documentation for Langkit is in `langkit/doc`. You can
consult it as a text files or you can build it. For instance, to generate HTML
documents, run from the top directory:

    $ make -C langkit/doc html

And then open the following file in your favorite browser:

    langkit/doc/_build/html/index.html

Bootstrapping a new language engine
-----------------------------------

Nothing is more simple than getting an initial project skeleton to work on a
new language engine. Imagine you want to create an engine for the Foo language,
run from the top-level directory:

    $ python langkit/create-project.py Foo

And then have a look at the created `foo` directory: you have minimal lexers
and parsers and a `manage.py` script you can use to build this new engine:

    $ python foo/manage.py make

Here you are!

Developer tools
---------------

Langkit uses mako templates generating Ada, C and Python code. This can be hard
to read. To ease development, Vim syntax files are available under the `utils`
directory (see `makoada.vim`, `makocpp.vim`). Install them in your
`$HOME/.vim/syntax` directory to get automatic highlighting of the template
files.
