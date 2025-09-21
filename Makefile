.PHONY: test

LUA_PATH := ./?.lua;./lib/?.lua;./lib/?/?.lua;./lib/comiclib/lib/?.lua;./lib/comiclib/third_party/?/?.lua""

test:
	LUA_PATH="$(LUA_PATH)" busted test
