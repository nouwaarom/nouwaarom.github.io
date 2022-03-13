---
layout: post
title:  "Semihosting: Printing to stdout" 
date:   2021-02-05
draft: true
description: "When using printf() when semihosting the printf function uses semihosting functions to print to the PC console. We will investigate how this works."
categories: semihosting libc
---

This is part two of a series, part one can be found [here]({{ site.baseurl }}{% link _posts/2021-01-30-investigating-semihosting.markdown %}).
In this post we will investigate how we can print using semihosting.
In the previous post we noticed that *puts* was used to print a string to stdout.
<!--more-->

## Reentrancy and opening stdout
Let us look at the definition of *puts*, which can be found in [puts.c](https://github.com/mirror/newlib-cygwin/blob/master/newlib/libc/stdio/puts.c).
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
We will investigate how reentrancy is guaranteed for this function.

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

Let us first look at the preprocessor statements to see which code will get compiled.
There is a conditional compilation on *_FVWRITE_IN_STREAMIO*.
With some googeling we find that this flag can be used to disable the io vector buffer. [source](https://sourceware.org/legacy-ml/newlib/2013/msg00146.html)
It turns out the buffer is available for newlib but not for newlib nano.
For the sake of simplicity we will explore the case without a buffer.
The flow of this function is a follows:
- Make sure the file to write to (stdout) is open.
- Get a lock on the file we want to write to.
- Write the string to this file character by character.
- Release the lock on the file.

## Making sure stdout is open
At the top of *_puts_r* we notice this code.
{% highlight c %}
  FILE *fp;
  _REENT_SMALL_CHECK_INIT (ptr);

  fp = _stdout_r (ptr);
  CHECK_INIT (ptr, fp);
{% endhighlight %}
First a file pointer is created. The _REENT_SMALL_CHECK_INIT(ptr) does nothing for our compile flags, so we ignore it.
The statement *_stdout_r* is defined in `stdio.h` as follows: 
{% highlight c %}
#define _stdout_r(x)	((x)->_stdout)
{% endhighlight %}
Which in our case expands to *ptr->_stdout*.

### The reentrancy struct
Notice that *ptr* is reference to the reentrancy structure (*_REENT*).
The macro *_REENT* expands to a global variable of type *struct _reent\**
The global variable is defined in `impure.c` as:
{% highlight c %}
static struct _reent __ATTRIBUTE_IMPURE_DATA__ impure_data = _REENT_INIT (impure_data);

struct _reent *__ATTRIBUTE_IMPURE_PTR__ _impure_ptr = &impure_data;
{% endhighlight %}
This structure is quite large. The definition is in `newlib/libc/include/sys/reent.h`

{% fold_highlight %}
{% highlight c %}
struct _reent
{
  int _errno;			/* local copy of errno */

  /* FILE is a big struct and may change over time.  To try to achieve binary
     compatibility with future versions, put stdin,stdout,stderr here.
     These are pointers into member __sf defined below.  */
  __FILE *_stdin, *_stdout, *_stderr;

//FOLD
  int  _inc;			/* used by tmpnam */
  char _emergency[_REENT_EMERGENCY_SIZE];

  /* TODO */
  int _unspecified_locale_info;	/* unused, reserved for locale stuff */
  struct __locale_t *_locale;/* per-thread locale */
//ENDFOLD
  int __sdidinit;		/* 1 means stdio has been init'd */

//FOLD
  void (*__cleanup) (struct _reent *);

  /* used by mprec routines */
  struct _Bigint *_result;
  int _result_k;
  struct _Bigint *_p5s;
  struct _Bigint **_freelist;

  /* used by some fp conversion routines */
  int _cvtlen;			/* should be size_t */
  char *_cvtbuf;

  union
    {
      struct
        {
          unsigned int _unused_rand;
          char * _strtok_last;
          char _asctime_buf[_REENT_ASCTIME_SIZE];
          struct __tm _localtime_buf;
          int _gamma_signgam;
          __extension__ unsigned long long _rand_next;
          struct _rand48 _r48;
          _mbstate_t _mblen_state;
          _mbstate_t _mbtowc_state;
          _mbstate_t _wctomb_state;
          char _l64a_buf[8];
          char _signal_buf[_REENT_SIGNAL_SIZE];
          int _getdate_err;
          _mbstate_t _mbrlen_state;
          _mbstate_t _mbrtowc_state;
          _mbstate_t _mbsrtowcs_state;
          _mbstate_t _wcrtomb_state;
          _mbstate_t _wcsrtombs_state;
	  int _h_errno;
        } _reent;
  /* Two next two fields were once used by malloc.  They are no longer
     used. They are used to preserve the space used before so as to
     allow addition of new reent fields and keep binary compatibility.   */
      struct
        {
#define _N_LISTS 30
          unsigned char * _nextf[_N_LISTS];
          unsigned int _nmalloc[_N_LISTS];
        } _unused;
    } _new;

# ifndef _REENT_GLOBAL_ATEXIT
  /* atexit stuff */
  struct _atexit *_atexit;	/* points to head of LIFO stack */
  struct _atexit _atexit0;	/* one guaranteed table, required by ANSI */
# endif

  /* signal info */
  void (**(_sig_func))(int);

  /* These are here last so that __FILE can grow without changing the offsets
     of the above members (on the off chance that future binary compatibility
     would be broken otherwise).  */
  struct _glue __sglue;		/* root of glue chain */
//ENDFOLD
# ifndef _REENT_GLOBAL_STDIO_STREAMS
  __FILE __sf[3];  		/* first three file descriptors */
# endif
};
{% endhighlight %}
{% endfold_highlight %}

This reentrancy struct is initialized by *_REENT_INIT*, which is defined in `reent.h`. 
In this macro the *_stdin*, *_stdout*, and *_stderror* elements are initialized with the addresses of *__sf[0]*, *__sf[1]* and *__sf[2]* respectively.
This means that these file pointers point to valid blocks of memory.

### Opening stdin, stdout and stderr
The files themeselves are not initialized yet, this is done by *CHECK_INIT(ptr)*.
This function checks if stdio is marked initialized, and if not initializes it:
{% highlight c %}
#define CHECK_INIT(ptr) \
#define CHECK_INIT(ptr, fp) \
  do								\
    {								\
      struct _reent *_check_init_ptr = (ptr);			\
      if ((_check_init_ptr) && !(_check_init_ptr)->__sdidinit)	\
	__sinit (_check_init_ptr);				\
    }								\
  while (0)
{% endhighlight %}
This weird looking do-while loop is added so that we can use this macro with a semicolon without a syntax error, as explained [here](https://stackoverflow.com/questions/154136/why-use-apparently-meaningless-do-while-and-if-else-statements-in-macros).

The definition of *__sinit* can be found in `findfp.c`:
{% fold_highlight %}
{% highlight c %}
/*
 * __sinit() is called whenever stdio's internal variables must be set up.
 */
void
__sinit (struct _reent *s)
{
  __sinit_lock_acquire ();

  if (s->__sdidinit)
    {
      __sinit_lock_release ();
      return;
    }

//FOLD
  /* make sure we clean up on exit */
  s->__cleanup = _cleanup_r;	/* conservative */

  s->__sglue._next = NULL;
#ifndef _REENT_SMALL
# ifndef _REENT_GLOBAL_STDIO_STREAMS
  s->__sglue._niobs = 3;
  s->__sglue._iobs = &s->__sf[0];
# endif /* _REENT_GLOBAL_STDIO_STREAMS */
#else
  s->__sglue._niobs = 0;
  s->__sglue._iobs = NULL;
  /* Avoid infinite recursion when calling __sfp  for _GLOBAL_REENT.  The
     problem is that __sfp checks for _GLOBAL_REENT->__sdidinit and calls
     __sinit if it's 0. */
  if (s == _GLOBAL_REENT)
    s->__sdidinit = 1;
# ifndef _REENT_GLOBAL_STDIO_STREAMS
  s->_stdin = __sfp(s);
  s->_stdout = __sfp(s);
  s->_stderr = __sfp(s);
# else /* _REENT_GLOBAL_STDIO_STREAMS */
  s->_stdin = &__sf[0];
  s->_stdout = &__sf[1];
  s->_stderr = &__sf[2];
# endif /* _REENT_GLOBAL_STDIO_STREAMS */
#endif

#ifdef _REENT_GLOBAL_STDIO_STREAMS
  if (__sf[0]._cookie == NULL) {
    _GLOBAL_REENT->__sglue._niobs = 3;
    _GLOBAL_REENT->__sglue._iobs = &__sf[0];
    stdin_init (&__sf[0]);
    stdout_init (&__sf[1]);
    stderr_init (&__sf[2]);
  }
//ENDFOLD
#else /* _REENT_GLOBAL_STDIO_STREAMS */
  stdin_init (s->_stdin);
  stdout_init (s->_stdout);
  stderr_init (s->_stderr);
#endif /* _REENT_GLOBAL_STDIO_STREAMS */

  s->__sdidinit = 1;

  __sinit_lock_release ();
}
{% endhighlight %}
{% endfold_highlight %}
The purpose of this post is researching how printing works, so we will discuss how stdout is opened. The code for stdin and stderr is very similar.
The only thing that *stdout_init* does is calling.
{% highlight c %}
  std (ptr, __SWR | __SLBF, 1);
{% endhighlight %}
The two flags mean that the file can be written to and that it is line buffered.
This means that the actual write will occur only when a newline character occurs (or a flush is executed).

{% fold_highlight %}
{% highlight c %}
static void
std (FILE *ptr,
            int flags,
            int file)
{
  ptr->_p = 0;
  ptr->_r = 0;
  ptr->_w = 0;
  ptr->_flags = flags;
  ptr->_flags2 = 0;
  ptr->_file = file;
  ptr->_bf._base = 0;
  ptr->_bf._size = 0;
  ptr->_lbfsize = 0;
  memset (&ptr->_mbstate, 0, sizeof (_mbstate_t));
  ptr->_cookie = ptr;
  ptr->_read = __sread;
#ifndef __LARGE64_FILES
  ptr->_write = __swrite;
#else /* __LARGE64_FILES */
//FOLD
  ptr->_write = __swrite64;
  ptr->_seek64 = __sseek64;
  ptr->_flags |= __SL64;
//ENDFOLD
#endif /* __LARGE64_FILES */
  ptr->_seek = __sseek;
#ifdef _STDIO_CLOSE_PER_REENT_STD_STREAMS
  ptr->_close = __sclose;
#else /* _STDIO_CLOSE_STD_STREAMS */
  ptr->_close = NULL;
#endif /* _STDIO_CLOSE_STD_STREAMS */
#if !defined(__SINGLE_THREAD__) && !(defined(_REENT_SMALL) && !defined(_REENT_GLOBAL_STDIO_STREAMS))
  __lock_init_recursive (ptr->_lock);
  /*
   * #else
   * lock is already initialized in __sfp
   */
#endif

//FOLD
#ifdef __SCLE
  if (__stextmode (ptr->_file))
    ptr->_flags |= __SCLE;
#endif
//ENDFOLD
}
{% endhighlight %}
{% endfold_highlight %}

Now we know how the file is opened and initialized and how all function pointers are set, let us continue our exploration.

## Locking a file (intermezzo)
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
It is not in the scope of this article to discuss the locking methods used, so we will not explain this further here.


## Printing a character 
Remember that in *_puts_r* all characters are written out with the following loop:
{% highlight c %}
  while (*p)
    {
      if (__sputc_r (ptr, *p++, fp) == EOF)
	goto err;
    }
  if (__sputc_r (ptr, '\n', fp) == EOF)
    goto err;
{% endhighlight %}
This loop calls *__sputc_r* for all characters in the string, until a string termintation character ('\\0') occurs or the file is full.
After that a newline is also printed using *__sputc_r*.

### Buffers and flushing
The definition of *sputc_r* can be found at `newlib/libc/include/sys/stdio.h`.
{% fold_highlight %}
{% highlight c %}
_ELIDABLE_INLINE int __sputc_r(struct _reent *_ptr, int _c, FILE *_p) {
//FOLD
#ifdef __SCLE
    if ((_p->_flags & __SCLE) && _c == '\n')
      __sputc_r (_ptr, '\r', _p);
#endif
//ENDFOLD
    if (--_p->_w >= 0 || (_p->_w >= _p->_lbfsize && (char)_c != '\n'))
        return (*_p->_p++ = _c);
    else
        return (__swbuf_r(_ptr, _c, _p));
}
{% endhighlight %}
{% endfold_highlight %}

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
We will not discuss the buffering here but we can see that 
*_fflush_r* is called if the buffer is full or if we the file is line buffered and we see a newline character.

The source of *_fflush_r* can be found in `newlib/libc/stdio/fflush.c`.
{% fold_highlight %}
{% highlight c %}
int
_fflush_r (struct _reent *ptr,
       register FILE * fp)
{
  int ret;

//FOLD
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
//ENDFOLD

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
//FOLD
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
//ENDFOLD
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
{% endfold_highlight %}
In this loop all characters are written using *fp->_write*.
This function returns the number of bytes written. If not all bytes could be written in the first call more calls are made for the rest of the data.
Remember that in the initialization this function pointer was assigned *__swrite*.

### Writing a character
The code for *__swrite* can be found in `stdio/stdio.c`.
{% fold_highlight %}
{% highlight c %}
_READ_WRITE_RETURN_TYPE
__swrite (struct _reent *ptr,
       void *cookie,
       char const *buf,
       _READ_WRITE_BUFSIZE_TYPE n)
{
  register FILE *fp = (FILE *) cookie;
  ssize_t w;
//FOLD
#ifdef __SCLE
  int oldmode=0;
#endif
//ENDFOLD

  if (fp->_flags & __SAPP)
    _lseek_r (ptr, fp->_file, (_off_t) 0, SEEK_END);
  fp->_flags &= ~__SOFF;	/* in case O_APPEND mode is set */

//FOLD
#ifdef __SCLE
  if (fp->_flags & __SCLE)
    oldmode = setmode (fp->_file, O_BINARY);
#endif
//ENDFOLD

  w = _write_r (ptr, fp->_file, buf, n);

//FOLD
#ifdef __SCLE
  if (oldmode)
    setmode (fp->_file, oldmode);
#endif
//ENDFOLD

  return w;
}
{% endhighlight %}
{% endfold_highlight %}
Stdout is not opened in append mode so we can ignore that part.
What is left is the call to *_write_r*.
This function is defined in `reent/writer.c`
{% highlight c %}
_ssize_t
_write_r (struct _reent *ptr,
     int fd,
     const void *buf,
     size_t cnt)
{
  _ssize_t ret;

  errno = 0;
  if ((ret = (_ssize_t)_write (fd, buf, cnt)) == -1 && errno != 0)
    ptr->_errno = errno;
  return ret;
}
{% endhighlight %}

The *_write* function is system specific. For arm it is defined in`sys/arm/syscalls.c` as:
{% highlight c %}
/* file, is a user file descriptor. */
int __attribute__((weak))
_write (int file, const void * ptr, size_t len)
{
  int slot = findslot (remap_handle (file));
  int x = _swiwrite (file, ptr, len);

  if (x == -1 || x == len)
    return error (-1);

  if (slot != MAX_OPEN_FILES)
    openfiles[slot].pos += len - x;

  return len - x;
}
{% endhighlight %}

Now we are finally there. In *_swiwrite* a block of data is written using semihosting.
{% fold_highlight %}
{% highlight c %}
/* file, is a valid internal file handle.
   Returns the number of bytes *not* written. */
int
_swiwrite (int file, const void * ptr, size_t len)
{
  int fh = remap_handle (file);
#ifdef ARM_RDI_MONITOR
  int block[3];

  block[0] = fh;
  block[1] = (int) ptr;
  block[2] = (int) len;

  return do_AngelSWI (AngelSWI_Reason_Write, block);
#else
//FOLD
  register int r0 asm("r0") = fh;
  register int r1 asm("r1") = (int) ptr;
  register int r2 asm("r2") = (int) len;

  asm ("swi %a4"
       : "=r" (r0)
       : "0"(fh), "r"(r1), "r"(r2), "i"(SWI_Write));
  return r0;
//ENDFOLD
#endif
}
{% endhighlight %}
{% endfold_highlight %}

## Conclusion
There is a lot of complicated code to write a string and there seems to be quite some overhead.
But the call to write bytes using semihosting is simple.

Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.
