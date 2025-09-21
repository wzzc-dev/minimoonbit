#!/bin/bash

moon run src/bin/main.mbt -- --end-stage parse $1
echo "Parsing done"
moon run src/bin/main.mbt -- --end-stage typecheck $1
echo "Typechecking done"
moon run src/bin/main.mbt -- --knf-interpreter $1
echo "Interpreting done"
moon run src/bin/main.mbt -- --closure-interpreter $1
echo "Closure interpreting done"