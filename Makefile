CFLAGS ?= -DNDEBUG -O3 -Wall -Wextra -pedantic -std=c99 -ftree-vectorize -msse2 -mfpmath=sse -fopt-info-vec-missed
#CFLAGS ?= -DNDEBUG -pg -Wall -Wextra -pedantic -std=c99
#CFLAGS ?= -DNDEBUG -c -Wall -Wextra -pedantic -std=c99
LDLIBS = -lm
#LDLIBS = -lm -pg
SOURCES := main.c renderer.c microui.c
OBJECTS := $(SOURCES:%.c=%.o)
DEPS := $(SOURCES:%.c=%.d)
CFLAGS += -MMD
TARGET = native
MAIN = main

$(MAIN): $(OBJECTS)
	$(CC) -o $(MAIN) $(OBJECTS) $(LDLIBS)

-include $(DEPS)

ifeq ($(OS),Windows_NT)
	MAIN = main.exe
	LDLIBS += -lgdi32
else ifeq ($(TARGET), mingw)
	MAIN = main.exe
	export CC = x86_64-w64-mingw32-gcc
	LDLIBS += -lgdi32
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S),Darwin)
		LDLIBS += -framework Cocoa
	else
		LDLIBS += -lX11
	endif
endif

clean:
	rm -f main $(OBJECTS) $(DEPS)

.PHONY: clean
