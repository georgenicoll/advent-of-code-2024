// From https://github.com/zigcc/zig-cookbook/blob/main/lib/regex_slim.c
#include "regex_slim.h"

regex_t* alloc_regex_t(void) {
  return (regex_t*)malloc(sizeof(regex_t));
}

void free_regex_t(regex_t* ptr) {
  free(ptr);
}