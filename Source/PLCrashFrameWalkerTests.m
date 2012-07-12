/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2009 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import <pthread.h>

#import "GTMSenTestCase.h"

#import "PLCrashFrameWalker.h"

@interface PLCrashFrameWalkerTests : SenTestCase {
@private
    plframe_test_thead_t _thr_args;
}
@end

@implementation PLCrashFrameWalkerTests
    
- (void) setUp {
    plframe_test_thread_spawn(&_thr_args);
}

- (void) tearDown {
    plframe_test_thread_stop(&_thr_args);
}

- (void) testGetRegName {
    for (int i = 0; i < PLFRAME_REG_LAST + 1; i++) {
        const char *name = plframe_get_regname(i);
        STAssertNotNULL(name, @"Register name for %d is NULL", i);
        STAssertNotEquals((size_t)0, strlen(name), @"Register name for %d is 0 length", i);
    }
}

/* test plframe_valid_stackaddr() */
- (void) testReadAddress {
    const char bytes[] = "Hello";
    char dest[sizeof(bytes)];

    // Verify that a good read succeeds
    plframe_read_addr(bytes, dest, sizeof(dest));
    STAssertTrue(strcmp(bytes, dest) == 0, @"Read was not performed");
    
    // Verify that reading off the page at 0x0 fails
    STAssertNotEquals(KERN_SUCCESS, plframe_read_addr(NULL, dest, sizeof(bytes)), @"Bad read was performed");
}


/* test plframe_cursor_init() */
- (void) testInitFrame {
    plframe_cursor_t cursor;

    /* Initialize the cursor */
    STAssertEquals(PLFRAME_ESUCCESS, plframe_cursor_thread_init(&cursor, pthread_mach_thread_np(_thr_args.thread)), @"Initialization failed");

    /* Try fetching the first frame */
    plframe_error_t ferr = plframe_cursor_next(&cursor);
    STAssertEquals(PLFRAME_ESUCCESS, ferr, @"Next failed: %s", plframe_strerror(ferr));

    /* Verify that all registers are supported */
    for (int i = 0; i < PLFRAME_REG_LAST + 1; i++) {
        plframe_greg_t val;
        STAssertEquals(PLFRAME_ESUCCESS, plframe_get_reg(&cursor, i, &val), @"Could not fetch register value");
    }
}

/* test plframe_getcontext() */
- (void) testGetContext {
#if __x86_64__
    _STRUCT_MCONTEXT ctx;
    memset(&ctx, 0, sizeof(ctx));
    
    uintptr_t expectedIP;
    plframe_error_t ret;

    uintptr_t leaqSize;
    __asm__ (
        "movq %[ctx], %%rdi\n"
        "call _plframe_getmcontext\n"
        "leaq (%%rip), %[eip]\n"
        "leaq (%%rip), %[leaqSize]\n"
        "movl %%eax, %[ret]\n"
        : [eip] "=r" (expectedIP), [ret] "=r" (ret), [leaqSize] "=r" (leaqSize)
        : [ctx] "r" (ctx)
        : "rdi", "eax"
    );

    STAssertEquals(PLFRAME_ESUCCESS, ret, @"Failed to fetch context");

    /* Adjust our computed IP to account for the size of the leaq instruction */
    expectedIP -= leaqSize - expectedIP;

    /* Validate IP. */
    STAssertEquals(expectedIP, ctx.__ss.__rip, @"Incorrect IP");

    /* Verify that RSP is sane. */
    uint8_t *stackaddr = pthread_get_stackaddr_np(pthread_self());
    size_t stacksize = pthread_get_stacksize_np(pthread_self());
    STAssertTrue((uint8_t *)ctx.__ss.__rsp < stackaddr && (uint8_t *)ctx.__ss.__rsp >= stackaddr-stacksize, @"RSP outside of stack range");
#elif __i386__
    _STRUCT_MCONTEXT ctx;
    memset(&ctx, 0, sizeof(ctx));
    
    uintptr_t expectedIP;    
    plframe_error_t ret = plframe_getmcontext(&ctx);
    __asm__ (
         "call Leip\n"
         "Leip: pop %0"
          : "=r" (expectedIP)
    );

    STAssertEquals(PLFRAME_ESUCCESS, ret, @"Failed to fetch context");
    
    /* Validate IP. Rather than handcode the call to plframe_getmcontext, we just sanity check the result. */
    STAssertTrue(expectedIP - (uintptr_t)ctx.__ss.__eip <= 20, @"Incorrect IP");
    
    /* Verify that ESP is sane. */
    uint8_t *stackaddr = pthread_get_stackaddr_np(pthread_self());
    size_t stacksize = pthread_get_stacksize_np(pthread_self());
    STAssertTrue((uint8_t *)ctx.__ss.__esp < stackaddr && (uint8_t *)ctx.__ss.__esp >= stackaddr-stacksize, @"ESP outside of stack range");

#elif __ARM__
#endif

}

@end
