; sha256_asm_windows.asm - Windows x64 SHA-256 File Hasher
; Compile: nasm -f win64 sha256_cli.asm -o sha256_cli.obj
; Link:    GoLink.exe /console /entry main sha256_cli.obj kernel32.dll shell32.dll

default rel

global main

extern ExitProcess
extern GetCommandLineW
extern CommandLineToArgvW
extern LocalFree
extern WriteFile
extern GetStdHandle
extern CreateFileA
extern ReadFile
extern CloseHandle

section .data
    msg_usage       db 'Usage: sha256.exe <filename>', 0Ah, 0Dh, 0
    msg_open_err    db 'Error: Could not open file.', 0Ah, 0Dh, 0
    newline         db 0Ah, 0Dh, 0
    ; SHA-256 Constants (K)
    K dd 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5
      dd 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174
      dd 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da
      dd 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967
      dd 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85
      dd 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070
      dd 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3
      dd 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ; Initial Hash Values (H)
    H_INIT dd 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    hex_table db "0123456789abcdef"

section .bss
    hStdOut         resq 1
    hFile           resq 1
    bytesRead       resd 1  
    dummy           resd 1  
    filename        resb 260

    ; SHA-256 ctx
    ; State: 8 x 32-bit integers (32 bytes)
    ctx_state       resd 8
    ; Data length (in bits): 64-bit integer
    ctx_datalen     resq 1
    ; Buffer: 64 bytes
    ctx_buf         resb 64
    ; Buffer Index (how many bytes currently in buffer)
    ctx_bufIdx      resd 1
    ; Read Buffer for File IO (4KB chunks)
    read_buf        resb 4096
    ; Output String Buffer (64 hex chars + newline + null)
    hex_output      resb 70

section .text

; -----------------------------------------------------------------------------
; ENTRY POINT
; -----------------------------------------------------------------------------
main:
    sub     rsp, 40                 ; Shadow space + alignment
    mov     rcx, -11                ; STD_OUTPUT_HANDLE
    call    GetStdHandle
    mov     [hStdOut], rax
    call    GetCommandLineW
    mov     rcx, rax
    lea     rdx, [rsp+32]           ; Pointer to receive argc (using shadow space temporarily)
    call    CommandLineToArgvW
    mov     r12, rax                ; R12 = pointer to argv array
    ; The stack slot [rsp+32] holds the integer value of argc.
    mov     eax, [rsp+32]
    cmp     eax, 2
    jl      .print_usage
    ; Get Argv[1] (Filename)
    mov     rcx, [r12 + 8]          ; Argv is array of pointers. Argv[1] is at offset 8 (64-bit)
    ; Convert Wide String (Argv[1]) to ANSI for CreateFileA
    lea     rdi, [filename]
    xor     rdx, rdx
.wstr_loop:
    movzx   ax, word [rcx + rdx*2]
    test    ax, ax
    jz      .wstr_done
    mov     [rdi + rdx], al
    inc     rdx
    cmp     rdx, 255
    jl      .wstr_loop
.wstr_done:
    mov     byte [rdi + rdx], 0
    ; Free argv memory
    mov     rcx, r12
    call    LocalFree
    ; Open the file
    lea     rcx, [filename]
    mov     rdx, 0x80000000         ; GENERIC_READ
    xor     r8, r8                  ; FILE_SHARE_READ (0 for simple)
    xor     r9, r9                  ; Security
    mov     qword [rsp+32], 3       ; OPEN_EXISTING
    mov     qword [rsp+40], 128     ; FILE_ATTRIBUTE_NORMAL
    mov     qword [rsp+48], 0       ; Template
    call    CreateFileA
    
    cmp     rax, -1                 ; INVALID_HANDLE_VALUE
    je      .file_error
    mov     [hFile], rax

    ; Initialize SHA256 Context
    call    sha256_init

    ; Read File Loop
.read_loop:
    mov     rcx, [hFile]
    lea     rdx, [read_buf]
    mov     r8d, 4096               ; Read 4KB chunks
    lea     r9, [bytesRead]
    mov     qword [rsp+32], 0       ; Overlapped = NULL
    call    ReadFile

    test    eax, eax                ; Check success
    jz      .close_file

    mov     eax, [bytesRead]
    test    eax, eax                ; Check EOF (0 bytes read)
    jz      .finish_hash

    ; Update Hash with buffer
    lea     rcx, [read_buf]
    mov     edx, eax                ; Length
    call    sha256_update
    jmp     .read_loop

.finish_hash:
    call    sha256_final
    lea     rsi, [ctx_state]        ; Source: Binary State
    lea     rdi, [hex_output]       ; Dest: String Buffer
    call    bin_to_hex

    ; Print Hash
    lea     rcx, [hex_output]
    call    print_sz

    ; Cleanup
.close_file:
    mov     rcx, [hFile]
    call    CloseHandle
    jmp     .exit

.file_error:
    lea     rcx, [msg_open_err]
    call    print_sz
    jmp     .exit

.print_usage:
    lea     rcx, [msg_usage]
    call    print_sz

.exit:
    mov     rcx, 0
    call    ExitProcess


print_sz:
    push    rbx
    push    rdi
    sub     rsp, 40
    mov     rdi, rcx                ; Save string ptr
    xor     rbx, rbx

.strlen:
    cmp     byte [rdi + rbx], 0
    je      .str_done
    inc     rbx
    jmp     .strlen
.str_done:
    mov     rcx, [hStdOut]
    mov     rdx, rdi
    mov     r8, rbx
    lea     r9, [dummy]
    mov     qword [rsp+32], 0
    call    WriteFile
    add     rsp, 40
    pop     rdi
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; RSI = Source (32 bytes binary)
; RDI = Destination (Buffer)
; -----------------------------------------------------------------------------
bin_to_hex:
    push    rbx
    push    rcx
    
    mov     rcx, 32                 ; 32 bytes to process
.hex_loop:
    movzx   eax, byte [rsi]         ; Load byte
    
    ; High Nibble
    mov     ebx, eax
    shr     ebx, 4
    mov     bl, [hex_table + rbx]
    mov     [rdi], bl
    inc     rdi
    
    ; Low Nibble
    and     eax, 0x0F
    mov     al, [hex_table + rax]
    mov     [rdi], al
    inc     rdi
    
    inc     rsi
    loop    .hex_loop
    
    ; Add newline and null
    mov     word [rdi], 0x0A0D
    mov     byte [rdi+2], 0
    
    pop     rcx
    pop     rbx
    ret


; -----------------------------------------------------------------------------
; SHA-256 FUNCTIONS
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; SHA256_INIT
; -----------------------------------------------------------------------------
sha256_init:
    ; Copy Initial Vector to State
    lea     rsi, [H_INIT]
    lea     rdi, [ctx_state]
    mov     ecx, 8
    rep movsd
    ; Reset counters
    mov     qword [ctx_datalen], 0
    mov     dword [ctx_bufIdx], 0
    ret

; -----------------------------------------------------------------------------
; SHA256_UPDATE
; RCX = Pointer to data
; RDX = Length in bytes
; -----------------------------------------------------------------------------
sha256_update:
    push    rbx
    push    r12
    push    r13
    mov     r12, rcx                ; Data Ptr
    mov     r13, rdx                ; Length
    
    ; Update Total Bit Count (Length * 8)
    mov     rax, r13
    shl     rax, 3
    add     [ctx_datalen], rax
    
    xor     rbx, rbx                ; Current input index
    
.update_loop:
    cmp     rbx, r13
    jge     .update_done
    ; Copy byte --> buffer
    mov     eax, [ctx_bufIdx]
    mov     r8b, [r12 + rbx]
    mov     [ctx_buf + rax], r8b
    ; Increment indexs
    inc     rbx
    inc     dword [ctx_bufIdx]
    ; Check if buf full (64 bytes)
    cmp     dword [ctx_bufIdx], 64
    jne     .update_loop
    ; Buf full, process block
    push    rbx
    push    r12
    push    r13
    lea     rcx, [ctx_buf]
    call    sha256_transform
    pop     r13
    pop     r12
    pop     rbx
    
    mov     dword [ctx_bufIdx], 0
    jmp     .update_loop
    
.update_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; SHA256_FINAL
; Pads the message and produces final hash
; -----------------------------------------------------------------------------
sha256_final:
    ; 1. Append '1' bit (0x80 byte)
    mov     eax, [ctx_bufIdx]
    mov     byte [ctx_buf + rax], 0x80
    inc     dword [ctx_bufIdx]
    ; 2. Check if enough space for length (needs 8 bytes at end, so 64-8=56)
    cmp     dword [ctx_bufIdx], 56
    jle     .pad_zeros
    ; Not enough space, pad with zeros to end, transform, then new block
    mov     ecx, [ctx_bufIdx]
.pad_loop_1:
    cmp     ecx, 64
    jge     .pad_transform_1
    mov     byte [ctx_buf + ecx], 0
    inc     ecx
    jmp     .pad_loop_1
.pad_transform_1:
    lea     rcx, [ctx_buf]
    call    sha256_transform
    mov     dword [ctx_bufIdx], 0   ; Reset for next block containing length
.pad_zeros:
    ; Pad with zeros until index 56
    mov     ecx, [ctx_bufIdx]
.pad_loop_2:
    cmp     ecx, 56
    jge     .append_len
    mov     byte [ctx_buf + ecx], 0
    inc     ecx
    jmp     .pad_loop_2
    
.append_len:
    ; Append 64-bit Big-Endian Bit Count
    mov     rax, [ctx_datalen]
    bswap   rax                     ; Convert to Big Endian
    mov     [ctx_buf + 56], rax
    ; Transform final block
    lea     rcx, [ctx_buf]
    call    sha256_transform
    ; Convert internal State -> Big Endian for output
    lea     rdi, [ctx_state]
    mov     ecx, 8
.endian_fix:
    mov     eax, [rdi]
    bswap   eax
    mov     [rdi], eax
    add     rdi, 4
    loop    .endian_fix
    
    ret

; -----------------------------------------------------------------------------
; SHA256_TRANSFORM
; RCX = Pointer to 64-byte block
; Internal function: Updates ctx_state based on block
; -----------------------------------------------------------------------------
sha256_transform:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 328                ; Stack buffer (W array 64*4) + variables
    ; RDI will point to W array on stack
    lea     rdi, [rsp]
    mov     rsi, rcx                ; Source data
    ; 1. Prepare Message Schedule W (0..15)
    ; Copy and bswap
    mov     ecx, 16
.w_copy:
    mov     eax, [rsi]
    bswap   eax
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    loop    .w_copy
    ; 2. Expand W (16..63)
    mov     ecx, 16
.w_expand:
    ; s0 = (w[i-15] rotr 7) ^ (w[i-15] rotr 18) ^ (w[i-15] shr 3)
    mov     eax, [rsp + (rcx-15)*4]
    mov     ebx, eax
    mov     edx, eax
    ror     eax, 7
    ror     ebx, 18
    shr     edx, 3
    xor     eax, ebx
    xor     eax, edx                ; EAX = s0
    ; s1 = (w[i-2] rotr 17) ^ (w[i-2] rotr 19) ^ (w[i-2] shr 10)
    mov     r8d, [rsp + (rcx-2)*4]
    mov     ebx, r8d
    mov     edx, r8d
    ror     r8d, 17
    ror     ebx, 19
    shr     edx, 10
    xor     r8d, ebx
    xor     r8d, edx                ; R8D = s1
    ; w[i] = w[i-16] + s0 + w[i-7] + s1
    mov     r9d, [rsp + (rcx-16)*4]
    add     r9d, eax                ; + s0
    add     r9d, [rsp + (rcx-7)*4]
    add     r9d, r8d                ; + s1
    mov     [rsp + rcx*4], r9d
    inc     ecx
    cmp     ecx, 64
    jl      .w_expand
    ; 3. init Working Variables
    ; Load current state into registers (a..h)
    ; Using r8..r15 for a..h
    mov     r8d,  [ctx_state + 0]   ; a
    mov     r9d,  [ctx_state + 4]   ; b
    mov     r10d, [ctx_state + 8]   ; c
    mov     r11d, [ctx_state + 12]  ; d
    mov     r12d, [ctx_state + 16]  ; e
    mov     r13d, [ctx_state + 20]  ; f
    mov     r14d, [ctx_state + 24]  ; g
    mov     r15d, [ctx_state + 28]  ; h
    
    xor     rcx, rcx                ; Loop counter t
    
.compression_loop:
    ; S1 = (e rotr 6) ^ (e rotr 11) ^ (e rotr 25)
    mov     eax, r12d
    mov     ebx, r12d
    mov     edx, r12d
    ror     eax, 6
    ror     ebx, 11
    ror     edx, 25
    xor     eax, ebx
    xor     eax, edx                ; EAX = S1
    
    ; ch = (e & f) ^ (~e & g)
    mov     ebx, r12d
    and     ebx, r13d               ; e & f
    mov     edx, r12d
    not     edx
    and     edx, r14d               ; ~e & g
    xor     ebx, edx                ; EBX = ch
    
    ; temp1 = h + S1 + ch + k[t] + w[t]
    mov     edx, r15d               ; h
    add     edx, eax                ; + S1
    add     edx, ebx                ; + ch
    add     edx, [K + rcx*4]        ; + k
    add     edx, [rsp + rcx*4]      ; + w
                                    ; EDX = temp1
                                    
    ; S0 = (a rotr 2) ^ (a rotr 13) ^ (a rotr 22)
    mov     eax, r8d
    mov     ebx, r8d
    push    rdx                     ; Free up a reg for S0 calculation
    mov     edx, r8d
    ror     eax, 2
    ror     ebx, 13
    ror     edx, 22
    xor     eax, ebx
    xor     eax, edx                ; EAX = S0
    pop     rdx                     ; Restore temp1
    
    ; maj = (a & b) ^ (a & c) ^ (b & c)
    mov     ebx, r8d
    and     ebx, r9d                ; a & b
    push    rdx                     ; Save temp1
    mov     edx, r8d
    and     edx, r10d               ; a & c
    xor     ebx, edx
    mov     edx, r9d
    and     edx, r10d               ; b & c
    xor     ebx, edx                ; EBX = maj
    pop     rdx                     ; Restore temp1
    
    ; temp2 = S0 + maj
    add     eax, ebx                ; EAX = temp2
    
    ; Rotate variables
    ; h = g
    ; g = f
    ; f = e
    ; e = d + temp1
    ; d = c
    ; c = b
    ; b = a
    ; a = temp1 + temp2
    
    mov     r15d, r14d
    mov     r14d, r13d
    mov     r13d, r12d
    mov     r12d, r11d
    add     r12d, edx               ; e = d + temp1
    mov     r11d, r10d
    mov     r10d, r9d
    mov     r9d, r8d
    mov     r8d, edx
    add     r8d, eax                ; a = temp1 + temp2
    inc     rcx
    cmp     rcx, 64
    jl      .compression_loop
    
    ; add working variables -> current state
    add     [ctx_state + 0],  r8d
    add     [ctx_state + 4],  r9d
    add     [ctx_state + 8],  r10d
    add     [ctx_state + 12], r11d
    add     [ctx_state + 16], r12d
    add     [ctx_state + 20], r13d
    add     [ctx_state + 24], r14d
    add     [ctx_state + 28], r15d
    
    add     rsp, 328
    pop     rbp
    ret