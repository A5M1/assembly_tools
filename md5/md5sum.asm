default rel

global start

extern GetStdHandle
extern WriteFile
extern CreateFileA
extern ReadFile
extern CloseHandle
extern ExitProcess
extern GetCommandLineW
extern CommandLineToArgvW
extern LocalFree
extern FlushFileBuffers

section .data
    usage_msg db "Usage: md5sum <filename>", 13, 10, 0
    err_msg db "Error reading file", 13, 10, 0
    hex_digits db "0123456789abcdef"
    
    ; MD5 Constants (K table)
    k_table dd 0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee
            dd 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501
            dd 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be
            dd 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821
            dd 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa
            dd 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8
            dd 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed
            dd 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a
            dd 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c
            dd 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70
            dd 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05
            dd 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665
            dd 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039
            dd 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1
            dd 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1
            dd 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391

    ; Initial Hash State
    h0 dd 0x67452301
    h1 dd 0xefcdab89
    h2 dd 0x98badcfe
    h3 dd 0x10325476

section .bss
    hStdOut resq 1
    handle resq 1
    read_len resd 1
    dummy resd 1
    total_len resq 1
    buffer resb 64
    ctx resd 4
    out_buf resb 34
    filename resb 260
    
section .text

start:
    sub rsp, 40
    mov rcx, -11
    call GetStdHandle
    mov [hStdOut], rax

    call GetCommandLineW
    mov rcx, rax
    lea rdx, [rsp+32]
    call CommandLineToArgvW
    mov r12, rax
    mov eax, [rsp+32]
    cmp eax, 2
    jl near .show_usage

    ; Convert WCHAR filename to MultiByte
    mov rcx, [r12 + 8]
    lea rdi, [filename]
    xor rdx, rdx
.wstr_loop:
    movzx ax, word [rcx + rdx*2]
    test ax, ax
    jz near .wstr_done
    mov [rdi + rdx], al
    inc rdx
    cmp rdx, 255
    jl near .wstr_loop
.wstr_done:
    mov byte [rdi + rdx], 0
    
    mov rcx, r12
    call LocalFree

    ; Open File
    lea rcx, [filename]
    mov rdx, 0x80000000 ; GENERIC_READ
    xor r8, r8
    xor r9, r9
    mov qword [rsp+32], 3 ; OPEN_EXISTING
    mov qword [rsp+40], 128 ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    
    cmp rax, -1
    je near .file_error
    mov [handle], rax

    ; Init Context
    mov eax, [h0]
    mov [ctx], eax
    mov eax, [h1]
    mov [ctx+4], eax
    mov eax, [h2]
    mov [ctx+8], eax
    mov eax, [h3]
    mov [ctx+12], eax
    
    mov qword [total_len], 0

.read_loop:
    mov rcx, [handle]
    lea rdx, [buffer]
    mov r8, 64
    lea r9, [read_len]
    mov qword [rsp+32], 0
    call ReadFile
    
    test rax, rax
    jz near .file_error
    
    mov eax, [read_len]
    add [total_len], rax
    cmp eax, 64
    jne near .padding
    
    lea rcx, [buffer]
    call md5_block
    jmp near .read_loop

.padding:
    mov rdi, buffer
    mov eax, [read_len]
    add rdi, rax
    mov byte [rdi], 0x80
    inc rdi
    mov eax, [read_len]
    inc eax  ; Account for the 0x80 byte we just added
    mov ecx, 56
    sub ecx, eax
    jns .pad_zeros  ; If ecx >= 0, jump
    add ecx, 64     ; Otherwise, add 64 to get positive count

.pad_zeros:
    test ecx, ecx
    jz .append_len  ; If ecx == 0, skip zero padding
    
    xor al, al
    rep stosb

.append_len:
    mov rax, [total_len]
    shl rax, 3      ; Convert bytes to bits
    
    ; Store low 32 bits
    mov dword [buffer+56], eax
    
    ; Store high 32 bits (should be 0 for files < 2^32 bits)
    shr rax, 32
    mov dword [buffer+60], eax
    
    lea rcx, [buffer]
    call md5_block
    
    call print_hash
	ret  ; Add this

.file_error:
    lea rcx, [err_msg]
    call print_sz
    mov ecx, 1
    call ExitProcess

.show_usage:
    lea rcx, [usage_msg]
    call print_sz
    mov ecx, 1
    call ExitProcess

print_sz:
    push rbx
    push rdi
    sub rsp, 40
    mov rdi, rcx
    xor rbx, rbx
.strlen:
    cmp byte [rdi + rbx], 0
    je near .str_done
    inc rbx
    jmp near .strlen
.str_done:
    mov rcx, [hStdOut]
    mov rdx, rdi
    mov r8, rbx
    lea r9, [dummy]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 40
    pop rdi
    pop rbx
    ret

print_hash:
    push rbx
    push rbp
    push rdi
    push rsi
    sub rsp, 40
    
    lea rdi, [out_buf]
    lea rsi, [ctx]
    mov ecx, 16
    
.hex_loop:
    movzx eax, byte [rsi]
    
    mov edx, eax
    shr edx, 4
    movzx r8d, byte [hex_digits + rdx]
    mov [rdi], r8b
    
    mov edx, eax
    and edx, 0xF
    movzx r8d, byte [hex_digits + rdx]
    mov [rdi+1], r8b
    
    add rdi, 2
    inc rsi
    dec ecx
    jnz .hex_loop
    
    mov word [rdi], 0x0A0D
    
    mov rcx, [hStdOut]
    lea rdx, [out_buf]
    mov r8, 34
    lea r9, [dummy]
    mov qword [rsp+32], 0
    call WriteFile
    
    add rsp, 40
    pop rsi
    pop rdi
    pop rbp
    pop rbx
    ret


; F = (x & y) | (~x & z) -> ((y ^ z) & x) ^ z
%macro STEP_F 8
    mov eax, %3     ; y
    xor eax, %4     ; z
    and eax, %2     ; x
    xor eax, %4     ; z
    add %1, eax     ; a += F result
    add %1, [%6 + %5 * 4] ; a += M[k]
    add %1, %7      ; a += K[i]
    rol %1, %8      ; Rotate by s
    add %1, %2      ; a += b
%endmacro

; G = (x & z) | (y & ~z) -> ((x ^ y) & z) ^ y
%macro STEP_G 8
    mov eax, %2     ; x
    xor eax, %3     ; y
    and eax, %4     ; z
    xor eax, %3     ; y
    add %1, eax
    add %1, [%6 + %5 * 4]
    add %1, %7
    rol %1, %8
    add %1, %2
%endmacro

; H = x ^ y ^ z
%macro STEP_H 8
    mov eax, %2     ; x
    xor eax, %3     ; y
    xor eax, %4     ; z
    add %1, eax
    add %1, [%6 + %5 * 4]
    add %1, %7
    rol %1, %8
    add %1, %2
%endmacro

; I = y ^ (x | ~z)
%macro STEP_I 8
    mov eax, %4     ; z
    not eax         ; ~z
    or  eax, %2     ; x | ~z
    xor eax, %3     ; y ^ (x | ~z)
    add %1, eax
    add %1, [%6 + %5 * 4]
    add %1, %7
    rol %1, %8
    add %1, %2
%endmacro

md5_block:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    
    mov r8d, [ctx]
    mov r9d, [ctx+4]
    mov r10d, [ctx+8]
    mov r11d, [ctx+12]
    
    mov r12, rcx

    ; Round 1
    STEP_F r8d, r9d, r10d, r11d, 0, r12, 0xd76aa478, 7
    STEP_F r11d, r8d, r9d, r10d, 1, r12, 0xe8c7b756, 12
    STEP_F r10d, r11d, r8d, r9d, 2, r12, 0x242070db, 17
    STEP_F r9d, r10d, r11d, r8d, 3, r12, 0xc1bdceee, 22
    STEP_F r8d, r9d, r10d, r11d, 4, r12, 0xf57c0faf, 7
    STEP_F r11d, r8d, r9d, r10d, 5, r12, 0x4787c62a, 12
    STEP_F r10d, r11d, r8d, r9d, 6, r12, 0xa8304613, 17
    STEP_F r9d, r10d, r11d, r8d, 7, r12, 0xfd469501, 22
    STEP_F r8d, r9d, r10d, r11d, 8, r12, 0x698098d8, 7
    STEP_F r11d, r8d, r9d, r10d, 9, r12, 0x8b44f7af, 12
    STEP_F r10d, r11d, r8d, r9d, 10, r12, 0xffff5bb1, 17
    STEP_F r9d, r10d, r11d, r8d, 11, r12, 0x895cd7be, 22
    STEP_F r8d, r9d, r10d, r11d, 12, r12, 0x6b901122, 7
    STEP_F r11d, r8d, r9d, r10d, 13, r12, 0xfd987193, 12
    STEP_F r10d, r11d, r8d, r9d, 14, r12, 0xa679438e, 17
    STEP_F r9d, r10d, r11d, r8d, 15, r12, 0x49b40821, 22

    ; Round 2
    STEP_G r8d, r9d, r10d, r11d, 1, r12, 0xf61e2562, 5
    STEP_G r11d, r8d, r9d, r10d, 6, r12, 0xc040b340, 9
    STEP_G r10d, r11d, r8d, r9d, 11, r12, 0x265e5a51, 14
    STEP_G r9d, r10d, r11d, r8d, 0, r12, 0xe9b6c7aa, 20
    STEP_G r8d, r9d, r10d, r11d, 5, r12, 0xd62f105d, 5
    STEP_G r11d, r8d, r9d, r10d, 10, r12, 0x02441453, 9
    STEP_G r10d, r11d, r8d, r9d, 15, r12, 0xd8a1e681, 14
    STEP_G r9d, r10d, r11d, r8d, 4, r12, 0xe7d3fbc8, 20
    STEP_G r8d, r9d, r10d, r11d, 9, r12, 0x21e1cde6, 5
    STEP_G r11d, r8d, r9d, r10d, 14, r12, 0xc33707d6, 9
    STEP_G r10d, r11d, r8d, r9d, 3, r12, 0xf4d50d87, 14
    STEP_G r9d, r10d, r11d, r8d, 8, r12, 0x455a14ed, 20
    STEP_G r8d, r9d, r10d, r11d, 13, r12, 0xa9e3e905, 5
    STEP_G r11d, r8d, r9d, r10d, 2, r12, 0xfcefa3f8, 9
    STEP_G r10d, r11d, r8d, r9d, 7, r12, 0x676f02d9, 14
    STEP_G r9d, r10d, r11d, r8d, 12, r12, 0x8d2a4c8a, 20

    ; Round 3
    STEP_H r8d, r9d, r10d, r11d, 5, r12, 0xfffa3942, 4
    STEP_H r11d, r8d, r9d, r10d, 8, r12, 0x8771f681, 11
    STEP_H r10d, r11d, r8d, r9d, 11, r12, 0x6d9d6122, 16
    STEP_H r9d, r10d, r11d, r8d, 14, r12, 0xfde5380c, 23
    STEP_H r8d, r9d, r10d, r11d, 1, r12, 0xa4beea44, 4
    STEP_H r11d, r8d, r9d, r10d, 4, r12, 0x4bdecfa9, 11
    STEP_H r10d, r11d, r8d, r9d, 7, r12, 0xf6bb4b60, 16
    STEP_H r9d, r10d, r11d, r8d, 10, r12, 0xbebfbc70, 23
    STEP_H r8d, r9d, r10d, r11d, 13, r12, 0x289b7ec6, 4
    STEP_H r11d, r8d, r9d, r10d, 0, r12, 0xeaa127fa, 11
    STEP_H r10d, r11d, r8d, r9d, 3, r12, 0xd4ef3085, 16
    STEP_H r9d, r10d, r11d, r8d, 6, r12, 0x04881d05, 23
    STEP_H r8d, r9d, r10d, r11d, 9, r12, 0xd9d4d039, 4
    STEP_H r11d, r8d, r9d, r10d, 12, r12, 0xe6db99e5, 11
    STEP_H r10d, r11d, r8d, r9d, 15, r12, 0x1fa27cf8, 16
    STEP_H r9d, r10d, r11d, r8d, 2, r12, 0xc4ac5665, 23

    ; Round 4
    STEP_I r8d, r9d, r10d, r11d, 0, r12, 0xf4292244, 6
    STEP_I r11d, r8d, r9d, r10d, 7, r12, 0x432aff97, 10
    STEP_I r10d, r11d, r8d, r9d, 14, r12, 0xab9423a7, 15
    STEP_I r9d, r10d, r11d, r8d, 5, r12, 0xfc93a039, 21
    STEP_I r8d, r9d, r10d, r11d, 12, r12, 0x655b59c3, 6
    STEP_I r11d, r8d, r9d, r10d, 3, r12, 0x8f0ccc92, 10
    STEP_I r10d, r11d, r8d, r9d, 10, r12, 0xffeff47d, 15
    STEP_I r9d, r10d, r11d, r8d, 1, r12, 0x85845dd1, 21
    STEP_I r8d, r9d, r10d, r11d, 8, r12, 0x6fa87e4f, 6
    STEP_I r11d, r8d, r9d, r10d, 15, r12, 0xfe2ce6e0, 10
    STEP_I r10d, r11d, r8d, r9d, 6, r12, 0xa3014314, 15
    STEP_I r9d, r10d, r11d, r8d, 13, r12, 0x4e0811a1, 21
    STEP_I r8d, r9d, r10d, r11d, 4, r12, 0xf7537e82, 6
    STEP_I r11d, r8d, r9d, r10d, 11, r12, 0xbd3af235, 10
    STEP_I r10d, r11d, r8d, r9d, 2, r12, 0x2ad7d2bb, 15
    STEP_I r9d, r10d, r11d, r8d, 9, r12, 0xeb86d391, 21

    add [ctx], r8d
    add [ctx+4], r9d
    add [ctx+8], r10d
    add [ctx+12], r11d
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret