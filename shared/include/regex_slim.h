// From https://github.com/zigcc/zig-cookbook/blob/main/lib/regex_slim.h
// Workaround for using regex in Zig.
// https://www.openmymind.net/Regular-Expressions-in-Zig/
// https://stackoverflow.com/questions/73086494/how-to-allocate-a-struct-of-incomplete-type-in-zig
#include <regex.h>
#include <stdlib.h>

/// Following taken from the re_pattern_buffer struct in regex.h and removing the
/// bitfields following re_nsub.   This allows us to get translate-c to run over this struct for use in
/// regex.zig
struct re_pattern_buffer_start
{
  /* Space that holds the compiled pattern.  The type
     'struct re_dfa_t' is private and is not declared here.  */
  struct re_dfa_t *__REPB_PREFIX(buffer);

  /* Number of bytes to which 'buffer' points.  */
  __re_long_size_t __REPB_PREFIX(allocated);

  /* Number of bytes actually used in 'buffer'.  */
  __re_long_size_t __REPB_PREFIX(used);

  /* Syntax setting with which the pattern was compiled.  */
  reg_syntax_t __REPB_PREFIX(syntax);

  /* Pointer to a fastmap, if any, otherwise zero.  re_search uses the
     fastmap, if there is one, to skip over impossible starting points
     for matches.  */
  char *__REPB_PREFIX(fastmap);

  /* Either a translate table to apply to all characters before
     comparing them, or zero for no translation.  The translation is
     applied to a pattern when it is compiled and to a string when it
     is matched.  */
  __RE_TRANSLATE_TYPE __REPB_PREFIX(translate);

  /* Number of subexpressions found by the compiler.  */
  size_t re_nsub;
};

regex_t* alloc_regex_t(void);
void free_regex_t(regex_t* ptr);