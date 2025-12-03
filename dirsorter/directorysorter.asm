;----------------------------------------------------------
;                       DirectorySorter.asm 
;                           MIT LICENSE
;                        (c)ABNSOFT 2025 
;----------------------------------------------------------
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this softwareandassociated documentation files(the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, andto permit persons to whom the Software is
;furnished to do so, subject to the following conditions :
;The above copyright noticeand this permission notice shall be included in
;all copies or substantial portions of the Software.
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL
;THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;DEALINGS IN THE SOFTWARE.
;----------------------------------------------------------

;----------------------------------------------------------
;nasm  -f win32 DirectorySorter.asm -o DirectorySorter.obj
;link/SUBSYSTEM:CONSOLE/ENTRY : _start DirectorySorter.obj kernel32.lib user32.lib
;golink /console /entry _start DirectorySorter.obj kernel32.dll user32.dll shell32.dll
;ld DirectorySorter.obj-o sorter.exe-e _start-lkernel32-luser32-lshell32 --subsystem=console
;polink DirectorySorter.obj/entry _start/subsystem console/out sorter.exe/dll kernel32.dll user32.dll shell32.dll
;gcc DirectorySorter.obj-o sorter.exe-lkernel32-luser32-lshell32
;----------------------------------------------------------

;----------------------------------------------------------
;Usage: sorter.exe <directory>
;----------------------------------------------------------
bits 32

extern  GetCommandLineA
extern  CommandLineToArgvW
extern  GetStdHandle
extern  WriteFile
extern  lstrcpyA
extern  lstrcatA
extern  CreateDirectoryA
extern  FindFirstFileA
extern  FindNextFileA
extern  FindClose
extern  MoveFileA
extern  ExitProcess
extern  WideCharToMultiByte

%define CP_ACP 0
global _start

section .data
findMask        db "*",0
slash           db "\",0
dotfilesStr     db "dotfiles",0
noextStr        db "noext",0
helpMsg         db "Usage: sorter.exe <directory>",13,10,0
helpLen         equ $-helpMsg
STD_OUTPUT_HANDLE equ -11

section .bss
findData        resb 320
dirPath         resb 260
dstDir          resb 260
dstPath         resb 260
utf8Buffer      resb 520
argCount        resd 1
argvPtr         resd 1
bytesOut        resd 1
section .text

print_help:
    push    STD_OUTPUT_HANDLE
    call    GetStdHandle
    push    bytesOut
    push    helpLen
    push    helpMsg
    push    eax
    call    WriteFile
    ret
_start:
    call    GetCommandLineA
    push    argCount
    push    eax
    call    CommandLineToArgvW
    mov     [argvPtr], eax
    mov     eax, [argCount]
    cmp     eax, 2
    jb      .help_and_exit
    mov     esi, [argvPtr]
    mov     esi, [esi+4]
    push    260
    push    utf8Buffer
    push    -1
    push    esi
    push    CP_ACP
    call    WideCharToMultiByte
    push    utf8Buffer
    push    dirPath
    call    lstrcpyA
    add     esp, 4
    call    SortDir
    push    0
    call    ExitProcess
.help_and_exit:
    call    print_help
    push    0
    call    ExitProcess
SortDir:
    push    dirPath
    push    dstDir
    call    lstrcpyA
    add     esp, 4
    push    slash
    push    dstDir
    call    lstrcatA
    add     esp, 4
    push    findMask
    push    dstDir
    call    lstrcatA
    add     esp, 4
    push    findData
    push    dstDir
    call    FindFirstFileA
    cmp     eax, -1
    je      .end
    mov     ebx, eax
.next_file:
    lea     esi, [findData+44]
    cmp     byte [esi], '.'
    jne     .notDotEntry
    cmp     byte [esi+1], 0
    je      .skip
    cmp     byte [esi+1], '.'
    jne     .notDotEntry
    cmp     byte [esi+2], 0
    je      .skip
.notDotEntry:
    cmp     byte [esi], '.'
    jne     .check_extension
    push    dirPath
    push    dstDir
    call    lstrcpyA
    add     esp,4
    push    slash
    push    dstDir
    call    lstrcatA
    add     esp,4
    push    dotfilesStr
    push    dstDir
    call    lstrcatA
    add     esp,8
    push    0
    push    dstDir
    call    CreateDirectoryA
    jmp     .build_full_dst
.check_extension:
    mov     edi, esi
.find_dot_loop:
    mov     al, [edi]
    cmp     al, 0
    je      .noext
    cmp     al, '.'
    je      .ext_found
    inc     edi
    jmp     .find_dot_loop
.noext:
    push    dirPath
    push    dstDir
    call    lstrcpyA
    add     esp,4
    push    slash
    push    dstDir
    call    lstrcatA
    add     esp,4
    push    noextStr
    push    dstDir
    call    lstrcatA
    add     esp,8
    push    0
    push    dstDir
    call    CreateDirectoryA
    jmp     .build_full_dst
.ext_found:
    inc     edi
    push    dirPath
    push    dstDir
    call    lstrcpyA
    add     esp, 4
    push    slash
    push    dstDir
    call    lstrcatA
    add     esp, 4
    push    edi
    push    dstDir
    call    lstrcatA
    add     esp, 8
    push    0
    push    dstDir
    call    CreateDirectoryA
.build_full_dst:
    push    dstDir
    push    dstPath
    call    lstrcpyA
    add     esp,4
    push    slash
    push    dstPath
    call    lstrcatA
    add     esp,4
    push    esi
    push    dstPath
    call    lstrcatA
    add     esp,8
    push    dirPath
    push    dstDir
    call    lstrcpyA
    add     esp,4
    push    slash
    push    dstDir
    call    lstrcatA
    add     esp,4
    push    esi
    push    dstDir
    call    lstrcatA
    add     esp,8
    push    dstPath
    push    dstDir
    call    MoveFileA
.skip:
    push    findData
    push    ebx
    call    FindNextFileA
    test    eax,eax
    jnz     .next_file
    push    ebx
    call    FindClose
.end:
    ret
