CWD=$(shell pwd)
NAME?=$(shell basename ${CWD})
ROOT?=${CWD}
DEPS=$(wildcard ${ROOT}/deps/*/ebin)
APPS=$(wildcard ${ROOT}/ebin)
REBAR?=${ROOT}/rebar -j 4
ERL?=/usr/bin/env erl
ERLARGS?=-pa ebin -pa ${DEPS} -smp enable -boot start_sasl -s lager
DIALYZER?=/usr/bin/env dialyzer
DIALYZER_OUT=${NAME}.plt
XREF_OUT=${CT_LOG}/xref.txt

all: clean getdeps compile

# Clean all.
clean:
	@${REBAR} clean

# Gets dependencies.
getdeps:
	@${REBAR} get-deps

# Compiles.
compile:
	@${REBAR} compile

# Compiles.
fastcompile:
	@${REBAR} compile skip_deps=true

# Dialyzer plt
${DIALYZER_OUT}:
	${DIALYZER} --verbose --build_plt -pa ${DEPS} --output_plt ${DIALYZER_OUT} \
		--apps kernel \
		stdlib \
		erts \
		compiler \
		hipe \
		crypto \
		edoc \
		gs \
		syntax_tools \
		tools \
		runtime_tools \
		inets \
		xmerl \
		ssl \
		mnesia \
		webtool

# Runs Dialyzer
analyze: compile ${DIALYZER_OUT} xref
	${DIALYZER} --verbose -pa ${DEPS} --plt ${DIALYZER_OUT} -Werror_handling \
		`find ${APP_DIR} -type f -name "${NAME}*.beam" | grep -v SUITE`

# Runs xref
xref:
	${REBAR} skip_deps=true xref

# Generates doc
doc:
	${REBAR} skip_deps=true doc 

# This one runs without a release.
shell: fastcompile
	${ERL} ${ERLARGS} -boot sasl -config priv/example -s safe_bunny
