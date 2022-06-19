#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

typedef uint16_t zig_ErrVoid;
typedef uint64_t zig_Usize;

typedef struct { uint64_t line; uint64_t column; char* file; char* code; }zig_IndividualTrace;
typedef struct { zig_IndividualTrace* trace; uint64_t len; char* error_name; }zig_StackTrace;

zig_ErrVoid usrMain();

static zig_IndividualTrace zig_possible_trace_1[3] = {
    {40, 8, "simple-ref-code-debug.c", "    if (!ok) /* unreachable begin: */ {"},
    {53, 19, "simple-ref-code-debug.c", "    stdDebugAssert(a == b, 24, 2);"},
    {45, 5, "simple-ref-code-debug.c", "    usrMain();"},
};
static zig_StackTrace zig_possible_unreachable_1 = { &zig_possible_trace_1, 3, "reached unreachable code" };

void zigUnreachable(zig_StackTrace full_trace) {
    printf("thread <TODO::list_thread_here> panic: %s\n", full_trace.error_name);
    uint64_t index = 0;
    while(index < full_trace.len){
        char buffer[512];
        printf("%s:%llu:%llu:\n", full_trace.trace[index].file, full_trace.trace[index].line, full_trace.trace[index].column);
        printf("%s\n", full_trace.trace[index].code);

        uint64_t i = 0;
        while(i<full_trace.trace[index].column) {buffer[i] = ' '; i++;}
        buffer[full_trace.trace[index].column - 1] = '^';
        buffer[full_trace.trace[index].column] = '\0';

        printf("%s\n", buffer);
        index++;
    } exit(0);
}

/* debug.zig:259:1 */ /* assert */
void stdDebugAssert(uint8_t ok, zig_StackTrace full_trace)  {
    if (!ok) zigUnreachable(full_trace); //* assertion failure *//
}

/* simple-ref-code.zig:3:1 */
int main() {
    usrMain();
}

/* simple-ref-code.zig:3:1 */
zig_ErrVoid usrMain() {
    /* simple-ref-code.zig:4:5 */
    const zig_Usize a = 1;
    const zig_Usize b = 2;
    stdDebugAssert(a == b, zig_possible_unreachable_1);
}