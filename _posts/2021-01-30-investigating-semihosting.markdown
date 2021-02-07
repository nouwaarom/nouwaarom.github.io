---
layout: post
title:  "Semihosting: initialize monitor"
date:   2021-01-30
description: "There are some posts and guides on how to setup semihosting, but almost none really explaning what is going on internally.
In this post I will dig deeper in to how it works."
categories: embedded c initialize_monitor_handles
---

When developing software for ARM microcontrollers there is a big chance that you want to use semihosting.
Using semihosting you can send debug messages over SWD of JTAG using the debugger.
This makes development easier as you do not need an other peripheral.
I found that setting up semihosting myself was quite confusing.
If you browse the internet there are some posts and guides on how to setup semihosting, but almost none really explaning what is going on internally.
In this post I will dig deeper in to how it works.
<!--more-->

## A simple example
We start with an example of how to use semihosting after that we will investigate what is going on.
Consider the following piece of code (`main.c`). Which uses semihosting to print over the debug console.
{% highlight c %}
#include <stdio.h>
extern void initialise_monitor_handles(void);
int main() {
    initialise_monitor_handles();
    printf("Hello!\n");

    return 0;
}
{% endhighlight %}
In this example I build for a cortex-m33 because that is the architecture I use. You can change the flags to compile it for other processors.
We can compile this using:
```
$ arm-none-eabi-gcc -nostdlib \
-marm -mcpu=cortex-m33 -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb \
-o main.o -c main.c
```
And link it using (this binary won't work, you need a linker script and startup files, which are mostly device specific.)
```
$ arm-none-eabi-gcc --specs=rdimon.specs -nostartfiles \
-marm -mcpu=cortex-m33 -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb \
-lc -lrdimon main.o -o main
```
The important flags for semihosting are: `--specs=rdimon.specs` and `-lrdimon`.
When you have a debug session using `gdb` you need to execute
`arm semihosting enable` or `monitor semihosting enable`.
Depending on the gdb server that you use (JLinkGDBServer, openocd, ...).

## Monitor Handles and the Angel SWI
The first thing we note it the function *initialise_monitor_handles*.
Without this function you cannot print over semihosting, but what does it do?
The implementation of this function in newlib can be found in the source of [newlib/libc/sys/arm/syscall.c](https://github.com/mirror/newlib-cygwin/blob/master/newlib/libc/sys/arm/syscalls.c).
{% highlight c %}
void
initialise_monitor_handles (void)
{
  int i;

  /* Open the standard file descriptors by opening the special
   * teletype device, ":tt", read-only to obtain a descriptor for
   * standard input and write-only to obtain a descriptor for standard
   * output. Finally, open ":tt" in append mode to obtain a descriptor
   * for standard error. Since this is a write mode, most kernels will
   * probably return the same value as for standard output, but the
   * kernel can differentiate the two using the mode flag and return a
   * different descriptor for standard error.
   */

#ifdef ARM_RDI_MONITOR
  int volatile block[3];

  block[0] = (int) ":tt";
  block[2] = 3;     /* length of filename */
  block[1] = 0;     /* mode "r" */
  monitor_stdin = do_AngelSWI (AngelSWI_Reason_Open, (void *) block);

  block[0] = (int) ":tt";
  block[2] = 3;     /* length of filename */
  block[1] = 4;     /* mode "w" */
  monitor_stdout = monitor_stderr
    = do_AngelSWI (AngelSWI_Reason_Open, (void *) block);
#else
  int fh;
  const char * name;

  name = ":tt";
  asm ("mov r0,%2; mov r1, #0; swi %a1; mov %0, r0"
       : "=r"(fh)
       : "i" (SWI_Open),"r"(name)
       : "r0","r1");
  monitor_stdin = fh;

  name = ":tt";
  asm ("mov r0,%2; mov r1, #4; swi %a1; mov %0, r0"
       : "=r"(fh)
       : "i" (SWI_Open),"r"(name)
       : "r0","r1");
  monitor_stdout = monitor_stderr = fh;
#endif

  for (i = 0; i < MAX_OPEN_FILES; i ++)
    openfiles[i].handle = -1;

  openfiles[0].handle = monitor_stdin;
  openfiles[0].pos = 0;
  openfiles[1].handle = monitor_stdout;
  openfiles[1].pos = 0;
}
{% endhighlight %}
We can see in this function opens the stdout and stdin file.
We require the stdout file for *printf* to work.
The preprocessor switch between `ARM_RDI_MONITOR` and it's counterpart `ARM_RDP_MONITOR` is very interesting.
It turns out that there are two debugging protocols: RDP which is also called Demon, and RDI which is also called Angel.
Now we have to figure out which protocol we are using.
When we look at the linker command we used previously, we notice `--specs=rdimon.specs` and `-lrdimon`. 
If we look at the contents of `rdimon.specs`, we see:
```
# rdimon.specs
#
# Spec file for AArch64 baremetal newlib with version 2 of the
# AngelAPI semi-hosting using the SVC trap instruction.
#
# This version supports extensibility through an extension mechanism.
```
So we are using RDI. 
Notice that in the same folder as, `lib/arm-none-eabi/newlib`, `rdimon.specs` there also is a `rdpmon.specs`.

With this informatin we now want to inspect `do_AngelSWI`.
We can find its implementation in
The implementation of this function in newlib can be found at [newlib/libc/sys/arm/swi.h](https://github.com/mirror/newlib-cygwin/blob/master/newlib/libc/sys/arm/swi.h).

{% highlight c %}
#include "arm.h"

/* SWI numbers for RDP (Demon) monitor.
 *
 * ...
 */


/* Now the SWI numbers and reason codes for RDI (Angel) monitors.  */
#define AngelSWI_ARM 			0x123456
#ifdef __thumb__
#define AngelSWI 			0xAB
#else
#define AngelSWI 			AngelSWI_ARM
#endif
/* For thumb only architectures use the BKPT instruction instead of SWI.  */
#ifdef THUMB_VXM
#define AngelSWIInsn			"bkpt"
#define AngelSWIAsm			bkpt
#else
#define AngelSWIInsn			"swi"
#define AngelSWIAsm			swi
#endif

/* The reason codes:  */
#define AngelSWI_Reason_Open		0x01
#define AngelSWI_Reason_Close		0x02
#define AngelSWI_Reason_WriteC		0x03
#define AngelSWI_Reason_Write0		0x04
#define AngelSWI_Reason_Write		0x05
#define AngelSWI_Reason_Read		0x06
#define AngelSWI_Reason_ReadC		0x07
#define AngelSWI_Reason_IsTTY		0x09
#define AngelSWI_Reason_Seek		0x0A
#define AngelSWI_Reason_FLen		0x0C
#define AngelSWI_Reason_TmpNam		0x0D
#define AngelSWI_Reason_Remove		0x0E
#define AngelSWI_Reason_Rename		0x0F
#define AngelSWI_Reason_Clock		0x10
#define AngelSWI_Reason_Time		0x11
#define AngelSWI_Reason_System		0x12
#define AngelSWI_Reason_Errno		0x13
#define AngelSWI_Reason_GetCmdLine 	0x15
#define AngelSWI_Reason_HeapInfo 	0x16
#define AngelSWI_Reason_EnterSVC 	0x17
#define AngelSWI_Reason_ReportException 0x18
#define ADP_Stopped_ApplicationExit 	((2 << 16) + 38)
#define ADP_Stopped_RunTimeError 	((2 << 16) + 35)

#if defined(ARM_RDI_MONITOR) && !defined(__ASSEMBLER__)

static inline int
do_AngelSWI (int reason, void * arg)
{
  int value;
  asm volatile ("mov r0, %1; mov r1, %2; " AngelSWIInsn " %a3; mov %0, r0"
       : "=r" (value) /* Outputs */
       : "r" (reason), "r" (arg), "i" (AngelSWI) /* Inputs */
       : "r0", "r1", "r2", "r3", "ip", "lr", "memory", "cc"
		/* Clobbers r0 and r1, and lr if in supervisor mode */);
                /* Accordingly to page 13-77 of ARM DUI 0040D other registers
                   can also be clobbered.  Some memory positions may also be
                   changed by a system call, so they should not be kept in
                   registers. Note: we are assuming the manual is right and
                   Angel is respecting the APCS.  */
  return value;
}

#endif
{% endhighlight %}
If we look at the documentation for `SYS_OPEN` at [developer.arm.com](https://developer.arm.com/documentation/dui0040/d/angel/angel-c-library-support-swis/sys-open--0x01-)
We can see that these calls open the console input and output `:tt`.
The function returns a file handle that can be used for further I/O operations.

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

The source of *puts* is quite complex. In order to keep this post to a reasonable length, we will explore this function in the next post.
Thank you for reading. If you have questions or suggestions, please open an issue or mergerequest on the [repository]({{ site.repo }}) for this site.
