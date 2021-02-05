---
layout: post
title:  "WIP: Investigating semihosting (2)"
date:   2021-02-05
description: "When using printf() when semihosting the printf function uses semihosting functions to print to the PC console. We will investigate how this works."
categories: embedded c semihosting puts 
---

This is part two of a series, part one can be found [here]({{ site.baseurl }}{% link _posts/2021-01-30-investigating-semihosting.markdown %}).
In this post we will investigate how we can print using semihosting.
In particular, we will explore how *puts* works.
<!--more-->

## Printing
When we look at the disassembly of main, which can be found by `$ arm-none-eabi-objdump --disassemble main.o`.
We see that the *printf* has been replaced by a call to *puts*.
 
```
main.o:     file format elf32-littlearm

Disassembly of section .text.main:
00000000 <main>:
   0:	b580      	push	{r7, lr}
   2:	af00      	add	r7, sp, #0
   4:	f7ff fffe 	bl	0 <initialise_monitor_handles>
   8:	4802      	ldr	r0, [pc, #8]	; (14 <main+0x14>)
   a:	f7ff fffe 	bl	0 <puts>
   e:	2300      	movs	r3, #0
  10:	4618      	mov	r0, r3
  12:	bd80      	pop	{r7, pc}
  14:	00000000 	.word	0x00000000
```

Let us look at the source of *puts*.
{% highlight c %}
/*
DESCRIPTION
<<puts>> writes the string at <[s]> (followed by a newline, instead of
the trailing null) to the standard output stream.

The alternate function <<_puts_r>> is a reentrant version.  The extra
argument <[reent]> is a pointer to a reentrancy structure.

RETURNS
If successful, the result is a nonnegative integer; otherwise, the
result is <<EOF>>.

PORTABILITY
ANSI C requires <<puts>>, but does not specify that the result on
success must be <<0>>; any non-negative value is permitted.

Supporting OS subroutines required: <<close>>, <<fstat>>, <<isatty>>,
<<lseek>>, <<read>>, <<sbrk>>, <<write>>.
*/

#include <_ansi.h>
#include <reent.h>
#include <stdio.h>
#include <string.h>
#include "fvwrite.h"
#include "local.h"

/*
 * Write the given string to stdout, appending a newline.
 */

int
_puts_r (struct _reent *ptr,
       const char * s)
{
#ifdef _FVWRITE_IN_STREAMIO // newlib
  int result;
  size_t c = strlen (s);
  struct __suio uio;
  struct __siov iov[2];
  FILE *fp;

  iov[0].iov_base = s;
  iov[0].iov_len = c;
  iov[1].iov_base = "\n";
  iov[1].iov_len = 1;
  uio.uio_resid = c + 1;
  uio.uio_iov = &iov[0];
  uio.uio_iovcnt = 2;

  _REENT_SMALL_CHECK_INIT (ptr);
  fp = _stdout_r (ptr);
  CHECK_INIT (ptr, fp);
  _newlib_flockfile_start (fp);
  ORIENT (fp, -1);
  result = (__sfvwrite_r (ptr, fp, &uio) ? EOF : '\n');
  _newlib_flockfile_end (fp);
  return result;
#else // newlib_nano
  int result = EOF;
  const char *p = s;
  FILE *fp;
  _REENT_SMALL_CHECK_INIT (ptr);

  fp = _stdout_r (ptr);
  CHECK_INIT (ptr, fp);
  _newlib_flockfile_start (fp);
  ORIENT (fp, -1);
  /* Make sure we can write.  */
  if (cantwrite (ptr, fp))
    goto err;

  while (*p)
    {
      if (__sputc_r (ptr, *p++, fp) == EOF)
	goto err;
    }
  if (__sputc_r (ptr, '\n', fp) == EOF)
    goto err;

  result = '\n';

err:
  _newlib_flockfile_end (fp);
  return result;
#endif
}

#ifndef _REENT_ONLY

int
puts (char const * s)
{
  return _puts_r (_REENT, s);
}

#endif
{% endhighlight %}
Let us first look at the preprocessor statements.
There is a conditional compilation on *_FVWRITE_IN_STREAMIO*.
With some googeling we find that this flag can be used to disable the io vector buffer. [source](https://sourceware.org/legacy-ml/newlib/2013/msg00146.html) 
It turns out the buffer is available for newlib but not for newlib nano. 


Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.
