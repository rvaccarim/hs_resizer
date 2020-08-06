;***********************   INCLUDE   ****************************
include \masm32\include\masm32rt.inc

;***********************  PROTOTYPES ****************************
Maximize            proto :HANDLE

;************************  STRUCTS   ****************************
MYRECT STRUCT
  left    SDWORD      ?
  top     SDWORD      ?
  right   SDWORD      ?
  bottom  SDWORD      ?
MYRECT ENDS

;***********************  CONSTANTS  **************************
HS_ICON               equ     1
ID_TIMER              equ     2
IDM_EXIT              equ     3
WM_SHELLNOTIFY        equ     WM_USER + 5

;*************************  DATA   ****************************
.data
szClassName           db "HS_Resizer_Class", 0
szDisplayName         db "Hearthstone Resizer", 0
szExit                db "Exit", 0
szMutex               db "HS_resizer", 0
szHearthstoneTitle    db "Hearthstone", 0
szBattlenetTitle      db "Blizzard Battle.net", 0
; Window handles
hHearthstone          HWND    0
hBattlenet            HWND    0
;
cntResizeAttempts     DWORD   0
maxResizeAttempts     DWORD   10
cntAppsNotFound       DWORD   0
maxAppsNotFound       DWORD   30
timeout               WORD    2000 ; milliseconds

.data?
hMutex                HANDLE  ?
hInstance             HMODULE ?
hResizerIcon          HANDLE  ?
hPopupMenu            HMENU   ?
notifyData            NOTIFYICONDATA <?>


;***************************  CODE   ***********************
.code
Resizer:   
    invoke  CreateMutex, NULL, FALSE, addr szMutex
    mov     hMutex, eax
    
    invoke  GetLastError
    cmp     eax, ERROR_ALREADY_EXISTS
    jne     Continue
    ; if it's already running then fine, end this instance
    jmp     Done
    
Continue:
    call    StartUp
    
Done:
    invoke  CloseHandle, hMutex
    invoke  ExitProcess, eax

StartUp proc
    LOCAL   msg:MSG
    LOCAL   wc:WNDCLASSEX

    invoke  GetModuleHandle, NULL
    mov     hInstance, eax
    
    ; we won't be using the other members of the structure so we init everything with zero
    invoke  memfill, addr wc, sizeof WNDCLASSEX, 0
    mov     wc.cbSize, sizeof WNDCLASSEX
    mov     wc.hInstance, eax
    mov     wc.lpszClassName, offset szClassName
    mov     wc.lpfnWndProc, offset WndProc

    ; Register the window and create it
    invoke  RegisterClassEx, addr wc
    invoke  CreateWindowEx, NULL, addr szClassName, addr szDisplayName, NULL, NULL, NULL, NULL, NULL, HWND_MESSAGE, \
                            NULL, hInstance, NULL
   
    .while TRUE
        invoke  GetMessage, addr msg, NULL, 0, 0
        .break .if !eax
        invoke  TranslateMessage, addr msg
        invoke  DispatchMessage, addr msg
    .endw
    mov     eax, msg.message       
    ret
StartUp endp

WndProc proc hWin:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
	LOCAL   pt:POINT

    .if uMsg == WM_CREATE
        ; create popup and add our only entry
        invoke  CreatePopupMenu
        mov     hPopupMenu, eax
        invoke  AppendMenu, hPopupMenu, MF_STRING, IDM_EXIT, addr szExit

        ; load our icon
        invoke  LoadImage, hInstance, HS_ICON, IMAGE_ICON, 0, 0, NULL
        mov     hResizerIcon, eax
       
        ; setup the tray icon
        mov     notifyData.cbSize, sizeof NOTIFYICONDATA
        push    hWin
        pop     notifyData.hwnd
        mov     notifyData.uID, 0
        mov     notifyData.uFlags, NIF_ICON or NIF_MESSAGE or NIF_TIP
        mov     notifyData.uCallbackMessage, WM_SHELLNOTIFY
        push    hResizerIcon
        pop     notifyData.hIcon
        invoke  lstrcpy, addr notifyData.szTip, addr szDisplayName    
        invoke  Shell_NotifyIcon, NIM_ADD, addr notifyData

        ; start timer, value is in milliseconds
        invoke  SetTimer, hWin, ID_TIMER, timeout, NULL
        
    .elseif uMsg == WM_COMMAND
        mov eax, wParam   
        	
        ; wParam's low-order word contains the control ID 
        ; EAX is the full 32-bit value, AX is the low-order 16-bits
        .if ax == IDM_EXIT
            ; wParam's high word stores the event
            ; shift the high word to the low word position
            shr eax, 16   

            .if ax == BN_CLICKED               
                invoke  SendMessage, hWin, WM_CLOSE, 0, 0
            .endif
        .endif

    .elseif uMsg == WM_SHELLNOTIFY
        .if wParam == 0
            .if lParam == WM_RBUTTONDOWN or WM_RBUTTONUP
                invoke  GetCursorPos, ADDR pt
                invoke  SetForegroundWindow, hWin
                invoke  TrackPopupMenuEx, hPopupMenu, TPM_LEFTALIGN or TPM_LEFTBUTTON, pt.x, pt.y, hWin, 0
                invoke  PostMessage, hWin, WM_NULL, 0, 0
            .endif
        .endif		
        
    .elseif uMsg == WM_TIMER

        invoke FindWindow, NULL, addr szBattlenetTitle
        mov hBattlenet, eax
        invoke Maximize, eax

        invoke FindWindow, NULL, addr szHearthstoneTitle
        mov hHearthstone, eax
        invoke Maximize, eax
        
        ; 10 iterations every 2000 milliseconds = 20 seconds
        ; it should be enough, we can quit.
        ; We start counting only after the Hearthstone window has
        ; been detected (not when BattleNet is opened)
        .if hHearthstone != NULL
            mov eax, maxResizeAttempts
            .if cntResizeAttempts == eax 
                invoke  SendMessage, hWin, WM_CLOSE, 0, 0
            .endif

            inc cntResizeAttempts
        .endif

        ; if we don't detect Batlle.Net and Hearthstone after a while 
        ; we also quit. This can happen if the user starts Battle.Net, then
        ; never starts Hearthstone for some reason, then quits Battle.Net
        ; and forgets to stop the utility manually
        .if hBattlenet == NULL && hHearthstone == NULL
            mov eax, maxAppsNotFound
            .if cntAppsNotFound == eax 
                invoke  SendMessage, hWin, WM_CLOSE, 0, 0
            .endif

            inc cntAppsNotFound
        .endif

    .elseif uMsg == WM_CLOSE 
        ; clean stuff
        invoke  Shell_NotifyIcon, NIM_DELETE, addr notifyData
        invoke  DestroyIcon, hResizerIcon
        invoke  DestroyMenu, hPopupMenu
        invoke  KillTimer, hWin, ID_TIMER
        invoke  ReleaseMutex, hMutex
        invoke  DestroyWindow, hWin
        
    .elseif uMsg == WM_DESTROY
        invoke PostQuitMessage, NULL
        
    .else
        invoke DefWindowProc, hWin, uMsg, wParam, lParam
        ret
    .endif
    xor    eax, eax
    ret

WndProc endp


Maximize proc targetHwnd : HWND
    LOCAL dlgRect : MYRECT
    
    .if targetHwnd != NULL
        invoke ShowWindow, targetHwnd, SW_MAXIMIZE  
    
        invoke GetWindowRect, targetHwnd, addr dlgRect
        .if eax != 0
            .if dlgRect.top >= 0 
                invoke ShowWindow, targetHwnd, SW_RESTORE  
                invoke ShowWindow, targetHwnd, SW_MAXIMIZE  
            .endif
        .endif
    .endif

    ret
Maximize endp

end Resizer