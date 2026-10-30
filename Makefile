# Builds the ask surface against a planner checkout's standalone headers.
PLANNER ?= ../rectgtn-domain-c-abi
CXX     ?= c++
CXXFLAGS = -std=gnu++20 -O2 -Wall
CPPFLAGS = -I$(PLANNER)/standalone

all: persona

persona: persona.cpp
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) $< -o $@

clean:
	rm -f persona

.PHONY: all clean
