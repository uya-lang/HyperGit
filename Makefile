UYA ?= $(HOME)/uya/uya/bin/uya
SRC := src/hgx/main.uya
BIN := bin/hgx
C99 := build/hgx.c

.PHONY: check build c99 test clean

check:
	$(UYA) check $(SRC)

build: $(BIN)

$(BIN): $(SRC)
	mkdir -p bin
	$(UYA) build $(SRC) -o $(BIN)

c99:
	mkdir -p build
	$(UYA) build $(SRC) -o $(C99) --c99

test:
	$(UYA) test src/hgx/test_cli_args.uya
	./tests/test_cli_golden.sh

clean:
	rm -f $(BIN) $(C99)
