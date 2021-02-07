---
layout: post
title:  "WIP: Semihosting: printing with puts" 
date:   2021-02-05
draft: true
description: "When using printf() when semihosting the printf function uses semihosting functions to print to the PC console. We will investigate how this works."
categories: embedded c semihosting puts
---

This is part two of a series, part one can be found [here]({{ site.baseurl }}{% link _posts/2021-01-30-investigating-semihosting.markdown %}).
In this post we will investigate how we can print using semihosting.
In the previous post we noticed that *puts* was used to print a string using semihosting.
Let us look at the definition of *puts*, which can be found in [puts.c](https://github.com/mirror/newlib-cygwin/blob/master/newlib/libc/stdio/puts.c).
<!--more-->

{% highlight c %}
int
puts (char const * s)
{
  return _puts_r (_REENT, s);
}
{% endhighlight %}
We notice that *puts* does nothing but call *_puts_r*.
The function *_puts_r* is reentrant. But what does it mean that a function is reentrant?
> In computing, a computer program or subroutine is called reentrant if multiple invocations can safely run concurrently on a single processor system, where a reentrant procedure can be interrupted in the middle of its execution and then safely be called again ("re-entered") before its previous invocations complete execution. - Wikipedia

It is very important that this function is reentrant as we want to be able to use it from the main loop and in interrupt handlers without our system crashing.
We will investigate how reentrancy is guaranteed for this function below.

{% fold_highlight %}
{% highlight c %}
//FOLD
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
//ENDFOLD

/*
 * Write the given string to stdout, appending a newline.
 */

int
_puts_r (struct _reent *ptr,
       const char * s)
{
#ifdef _FVWRITE_IN_STREAMIO // newlib
//FOLD
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
//ENDFOLD
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
{% endhighlight %}
{% endfold_highlight %}

Let us first look at the preprocessor statements.
There is a conditional compilation on *_FVWRITE_IN_STREAMIO*.
With some googeling we find that this flag can be used to disable the io vector buffer. [source](https://sourceware.org/legacy-ml/newlib/2013/msg00146.html)
It turns out the buffer is available for newlib but not for newlib nano.

For the sake of simplicity we will explore the case without a buffer.
The flow of this function is a follows:
- Get a lock on the file we want to write to.
- Write the string to this file character by character.
- Release the lock on the file.

## Locking a file
The functions *_newlib_flockfile_start* and *_newlib_flockfile_end* are used for file locking.
These functions are defined in `newlib/libc/stdio/local.h`, the implementation of *_flockfile* and *_funlockfile* are found in `newlib/libc/include/sys/stdio.h`.
We will combine them to make things a bit easier to read.
{% highlight c %}
#define _newlib_flockfile_start(_fp) \
    { \
        if (!(_fp->_flags2 & __SNLK)) \
          _flockfile (_fp)

#define _newlib_flockfile_exit(_fp) \
        if (!(_fp->_flags2 & __SNLK)) \
          _funlockfile(_fp); \

#define _newlib_flockfile_end(_fp) \
        if (!(_fp->_flags2 & __SNLK)) \
          _funlockfile(_fp); \
    }

#define _flockfile(fp) (((fp)->_flags & __SSTR) ? 0 : __lock_acquire_recursive((fp)->_lock))
#define _funlockfile(fp) (((fp)->_flags & __SSTR) ? 0 : __lock_release_recursive((fp)->_lock))
{% endhighlight %}
I found it quite cool that *_start* and *_end* define a scope together so that you have cannot forget to do an *_end*.


## Reentrancy
Reentrancy code is in `newlib/libc/include/sys/reent.h`

## Printing a character 
The definition of *sputc_r* can be found at `newlib/libc/include/sys/stdio.h`.
{% highlight c %}
_ELIDABLE_INLINE int __sputc_r(struct _reent *_ptr, int _c, FILE *_p) {
#ifdef __SCLE
    if ((_p->_flags & __SCLE) && _c == '\n')
      __sputc_r (_ptr, '\r', _p);
#endif
    if (--_p->_w >= 0 || (_p->_w >= _p->_lbfsize && (char)_c != '\n'))
        return (*_p->_p++ = _c);
    else
        return (__swbuf_r(_ptr, _c, _p));
}
{% endhighlight %}

The implementation of *__swbuf_r* can be found in `newlib/libc/stdio/wbuf.c`.
{% highlight c %}
/*
 * Write the given character into the (probably full) buffer for
 * the given file.  Flush the buffer out if it is or becomes full,
 * or if c=='\n' and the file is line buffered.
 */

int
__swbuf_r (struct _reent *ptr,
       register int c,
       register FILE *fp)
{
  register int n;

  /* Ensure stdio has been initialized.  */

  CHECK_INIT (ptr, fp);

  /*
   * In case we cannot write, or longjmp takes us out early,
   * make sure _w is 0 (if fully- or un-buffered) or -_bf._size
   * (if line buffered) so that we will get called again.
   * If we did not do this, a sufficient number of putc()
   * calls might wrap _w from negative to positive.
   */

  fp->_w = fp->_lbfsize;
  if (cantwrite (ptr, fp))
    return EOF;
  c = (unsigned char) c;

  ORIENT (fp, -1);

  /*
   * If it is completely full, flush it out.  Then, in any case,
   * stuff c into the buffer.  If this causes the buffer to fill
   * completely, or if c is '\n' and the file is line buffered,
   * flush it (perhaps a second time).  The second flush will always
   * happen on unbuffered streams, where _bf._size==1; fflush()
   * guarantees that putc() will always call wbuf() by setting _w
   * to 0, so we need not do anything else.
   */

  n = fp->_p - fp->_bf._base;
  if (n >= fp->_bf._size)
    {
      if (_fflush_r (ptr, fp))
	return EOF;
      n = 0;
    }
  fp->_w--;
  *fp->_p++ = c;
  if (++n == fp->_bf._size || (fp->_flags & __SLBF && c == '\n'))
    if (_fflush_r (ptr, fp))
      return EOF;
  return c;
}
{% endhighlight %}

The source of *_fflush_r* can be found in `newlib/libc/stdio/fflush.c`.
{% highlight c %}
int
_fflush_r (struct _reent *ptr,
       register FILE * fp)
{
  int ret;

#ifdef _REENT_SMALL
  /* For REENT_SMALL platforms, it is possible we are being
     called for the first time on a std stream.  This std
     stream can belong to a reentrant struct that is not
     _REENT.  If CHECK_INIT gets called below based on _REENT,
     we will end up changing said file pointers to the equivalent
     std stream off of _REENT.  This causes unexpected behavior if
     there is any data to flush on the _REENT std stream.  There
     are two alternatives to fix this:  1) make a reentrant fflush
     or 2) simply recognize that this file has nothing to flush
     and return immediately before performing a CHECK_INIT.  Choice
     2 is implemented here due to its simplicity.  */
  if (fp->_bf._base == NULL)
    return 0;
#endif /* _REENT_SMALL  */

  CHECK_INIT (ptr, fp);

  if (!fp->_flags)
    return 0;

  _newlib_flockfile_start (fp);
  ret = __sflush_r (ptr, fp);
  _newlib_flockfile_end (fp);
  return ret;
}


/* Flush a single file, or (if fp is NULL) all files.  */

/* Core function which does not lock file pointer.  This gets called
   directly from __srefill. */
int
__sflush_r (struct _reent *ptr,
       register FILE * fp)
{
  register unsigned char *p;
  register _READ_WRITE_BUFSIZE_TYPE n;
  register _READ_WRITE_RETURN_TYPE t;
  short flags;

  flags = fp->_flags;
  if ((flags & __SWR) == 0)
    {
#ifdef _FSEEK_OPTIMIZATION
      /* For a read stream, an fflush causes the next seek to be
         unoptimized (i.e. forces a system-level seek).  This conforms
         to the POSIX and SUSv3 standards.  */
      fp->_flags |= __SNPT;
#endif

      /* For a seekable stream with buffered read characters, we will attempt
         a seek to the current position now.  A subsequent read will then get
         the next byte from the file rather than the buffer.  This conforms
         to the POSIX and SUSv3 standards.  Note that the standards allow
         this seek to be deferred until necessary, but we choose to do it here
         to make the change simpler, more contained, and less likely
         to miss a code scenario.  */
      if ((fp->_r > 0 || fp->_ur > 0) && fp->_seek != NULL)
	{
	  int tmp_errno;
#ifdef __LARGE64_FILES
	  _fpos64_t curoff;
#else
	  _fpos_t curoff;
#endif

	  /* Save last errno and set errno to 0, so we can check if a device
	     returns with a valid position -1.  We restore the last errno if
	     no other error condition has been encountered. */
	  tmp_errno = ptr->_errno;
	  ptr->_errno = 0;
	  /* Get the physical position we are at in the file.  */
	  if (fp->_flags & __SOFF)
	    curoff = fp->_offset;
	  else
	    {
	      /* We don't know current physical offset, so ask for it.
		 Only ESPIPE and EINVAL are ignorable.  */
#ifdef __LARGE64_FILES
	      if (fp->_flags & __SL64)
		curoff = fp->_seek64 (ptr, fp->_cookie, 0, SEEK_CUR);
	      else
#endif
		curoff = fp->_seek (ptr, fp->_cookie, 0, SEEK_CUR);
	      if (curoff == -1L && ptr->_errno != 0)
		{
		  int result = EOF;
		  if (ptr->_errno == ESPIPE || ptr->_errno == EINVAL)
		    {
		      result = 0;
		      ptr->_errno = tmp_errno;
		    }
		  else
		    fp->_flags |= __SERR;
		  return result;
		}
            }
          if (fp->_flags & __SRD)
            {
              /* Current offset is at end of buffer.  Compensate for
                 characters not yet read.  */
              curoff -= fp->_r;
              if (HASUB (fp))
                curoff -= fp->_ur;
            }
	  /* Now physically seek to after byte last read.  */
#ifdef __LARGE64_FILES
	  if (fp->_flags & __SL64)
	    curoff = fp->_seek64 (ptr, fp->_cookie, curoff, SEEK_SET);
	  else
#endif
	    curoff = fp->_seek (ptr, fp->_cookie, curoff, SEEK_SET);
	  if (curoff != -1 || ptr->_errno == 0
	      || ptr->_errno == ESPIPE || ptr->_errno == EINVAL)
	    {
	      /* Seek successful or ignorable error condition.
		 We can clear read buffer now.  */
#ifdef _FSEEK_OPTIMIZATION
	      fp->_flags &= ~__SNPT;
#endif
	      fp->_r = 0;
	      fp->_p = fp->_bf._base;
	      if ((fp->_flags & __SOFF) && (curoff != -1 || ptr->_errno == 0))
		fp->_offset = curoff;
	      ptr->_errno = tmp_errno;
	      if (HASUB (fp))
		FREEUB (ptr, fp);
	    }
	  else
	    {
	      fp->_flags |= __SERR;
	      return EOF;
	    }
	}
      return 0;
    }
  if ((p = fp->_bf._base) == NULL)
    {
      /* Nothing to flush.  */
      return 0;
    }
  n = fp->_p - p;		/* write this much */

  /*
   * Set these immediately to avoid problems with longjmp
   * and to allow exchange buffering (via setvbuf) in user
   * write function.
   */
  fp->_p = p;
  fp->_w = flags & (__SLBF | __SNBF) ? 0 : fp->_bf._size;

  while (n > 0)
    {
      t = fp->_write (ptr, fp->_cookie, (char *) p, n);
      if (t <= 0)
	{
          fp->_flags |= __SERR;
          return EOF;
	}
      p += t;
      n -= t;
    }
  return 0;
}
{% endhighlight %}

Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.
