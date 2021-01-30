---
layout: post
title:  "WIP: Investigating semihosting"
date:   2021-01-30
categories: embedded, c
---

When developing software for arm microcontrollers there is a big chance that you want to use semihosting.
Using semihosting you can send debug messages over SWD of JTAG using the debugger. This makes development easier as you do not need an other peripheral.
I found that setting up semihosting myself was quite confusing. In this post I will dig deeper in to how it works and how we can set it up.
