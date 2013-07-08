REM >FortuneSrc
REM
REM Fortune Module
REM (c) Stephen Fryatt, 1997
REM
REM Needs ExtBasAsm to assemble.
REM 26/32 bit neutral

version$="1.10"
save_as$="Fortune"

LIBRARY "<Reporter$Dir>.AsmLib"

PRINT "Assemble debug? (Y/N)"
REPEAT
 g%=GET
UNTIL (g% AND &DF)=ASC("Y") OR (g% AND &DF)=ASC("N")
debug%=((g% AND &DF)=ASC("Y"))

ON ERROR PRINT REPORT$;" at line ";ERL : END

REM --------------------------------------------------------------------------------------------------------------------
REM Set up workspace

workspace_size%=0 : REM This is updated.

block%=FNworkspace(workspace_size%,256)

REM --------------------------------------------------------------------------------------------------------------------
REM Set up constants

shadow%=8
y_pos%=180

display_font$="Trinity.Bold"

REM --------------------------------------------------------------------------------------------------------------------

DIM time% 5, date% 256
?time%=3
SYS "OS_Word",14,time%
SYS "Territory_ConvertDateAndTime",-1,time%,date%,255,"(%dy %m3 %ce%yr)" TO ,date_end%
?date_end%=13

REM --------------------------------------------------------------------------------------------------------------------

code_space%=4000
DIM code% code_space%

pass_flags%=%11100

IF debug% THEN PROCReportInit(200)


FOR pass%=pass_flags% TO pass_flags% OR %10 STEP %10
L%=code%+code_space%
O%=code%
P%=0
IF debug% THEN PROCReportStart(pass%)
[OPT pass%
EXT 1
          EQUD      0                   ; Offset to task code
          EQUD      init_code           ; Offset to initialisation code
          EQUD      final_code          ; Offset to finalisation code
          EQUD      service_code        ; Offset to service-call handler
          EQUD      title_string        ; Offset to title string
          EQUD      help_string         ; Offset to help string
          EQUD      0                   ; Offset to command table
          EQUD      0                   ; SWI Chunk number
          EQUD      0                   ; Offset to SWI handler code
          EQUD      0                   ; Offset to SWI decoding table
          EQUD      0                   ; Offset to SWI decoding code
          EQUD      0                   ; MessageTrans file
          EQUD      module_flags        ; Offset to module flags

; ======================================================================================================================

.module_flags
          EQUD      1                   ; 32-bit compatible

; ======================================================================================================================

.title_string
          EQUZ      "Fortune"

.help_string
          EQUS      "Fortune Cookie"
          EQUB      9
          EQUS      version$
          EQUS      " "
          EQUS      $date%
          EQUZ      " © Stephen Fryatt, 1997"
          ALIGN

; ======================================================================================================================

.init_code

; Initialisation code

          STMFD     R13!,{R0-R11,R14}

; Check that the module hasn't already initialised (ie workspace pointer == 0)

          LDR       R0,[R12]
          TEQ       R0,#0
          BNE       init_exit

; Claim 256 bytes of workspace.

          MOV       R0,#6
          MOV       R3,#workspace_size%
          SWI       "XOS_Module"
          BVS       init_exit

          STR       R2,[R12]

.init_exit
          LDMFD     R13!,{R0-R11,PC}

; ======================================================================================================================

.final_code

; Finalisation code.

; See if the finalisation is fatal; if not, don't do anything.

          TEQ       R10,#0
          MOVEQ     PC,R14

          STMFD     R13!,{R14}

; Release the workspace and set the workspace pointer to zero.

          MOV       R0,#7
          LDR       R2,[R12]
          SWI       "XOS_Module"
          BVS       final_exit

          MOV       R0,#0
          STR       R0,[R12]

.final_exit
          LDMFD     R13!,{PC}

; ======================================================================================================================

.service_code

; The service call handler

; We only want Service_DesktopWelcome (&7C) so discard all others.

          TEQ       R1,#&7C
          MOVNE     PC,R14

.desktop_welcome

; Now we know that it is Service_DesktopWelcome, so set up registers and start on the banner.

          STMFD     R13!,{R0-R12,R14}

          LDR       R12,[R12]                     ; R12 -> Workspace

.open_cookie_file

          ADRW      R1,block%                     ; R1 -> Workspace block

; Use OS_GSTrans to evaluate <Welcome$FortuneFile> into the workspace.  The code is exited if
; the variable is unset or dues not exist.

          ADR       R0,file_system_variable
          MOV       R2,#255
          SWI       "XOS_GSTrans"
          BVS       service_done

          TEQ       R2,#0
          BEQ       service_done

; Open the cookie file, putting the handle in R0.  Exit if the file does not exist.

          MOV       R0,#&4F
          SWI       "XOS_Find"
          BVS       service_done

          TEQ       R0,#0
          BEQ       service_done

          MOV       R7,R0                         ; R7 == File handle

; Use OS_GSTrans to read in <Welcome$Fortunes>, the number of fortunes in the file.

          ADRL      R0,cookies_system_variable
          MOV       R2,#255
          SWI       "XOS_GSTrans"
          BVS       close_cookie_file_and_exit

          TEQ       R2,#0
          BEQ       close_cookie_file_and_exit

; Convert the number of fortunes from a string to a number.

          MOV       R0,#10                        ; Base 10
          SWI       "XOS_ReadUnsigned"
          BVS       close_cookie_file_and_exit

          MOV       R4,R2                         ; R4 == Number of cookies

; Load the RTC into the workspace, pointed to by R1

          MOV       R0,#14
          ADRW      R1,block%
          MOV       R3,#3
          STRB      R3,[R1]
          SWI       "XOS_Word"
          BVS       close_cookie_file_and_exit

; Calculate into R5 the minimum number of bits needed to store the number of cookies.  This is
; used as the number of bits we need to take from the RTC value.

          MOV       R5,#1                         ; R5 == Bit counter
          MOV       R6,#1                         ; R6 == Maximum value with this R5 bits

.bit_size_too_small
          CMP       R4,R6
          BLE       bit_size_ok
          ORR       R6,R6,R6,LSL #1
          ADD       R5,R5,#1
          B         bit_size_too_small

; Now that R5 contains the number of bits needed, subtract from 31 to give the number of bits not
; needed from the RTC.  These bits are then zeroed by shifting them out of the register.

.bit_size_ok
          RSB       R5,R5,#32

          LDR       R3,[R1]                        ; R3 == LSBs of RTC
          MOV       R3,R3,LSL R5
          MOV       R3,R3,LSR R5

; Bring the number into range by subtracting the number of cookies if necessary.

.number_too_big
          CMP       R3,R4
          BLE       number_ok
          SUB       R3,R3,R4
          B         number_too_big

; Finally make sure that the cookie number isn't 0 and set the filehandle up for OS_BGet.

.number_ok
          TEQ       R3,#0
          MOVEQ     R3,#1

          MOV       R1,R7                         ; R1 == File handle

; Read through the file line by line until the correct cookie is stored in the workspace buffer.

.enum_cookies
          BL        read_line
          BVS       close_cookie_file_and_exit
          SUBS      R3,R3,#1
          BNE       enum_cookies

; Close the cookie file once the fortune is in the buffer.

.close_cookie_file
          MOV       R0,#0
          SWI       "XOS_Find"
          BVS       service_done

; Read the size of the screen at the start of the Desktop.

.get_screen_mode_details
          MVN       R0,#NOT-1                     ; Current screen mode

          MOV       R1,#5
          SWI       "OS_ReadModeVariable"
          MOV       R3,R2
          MOV       R1,#12
          SWI       "OS_ReadModeVariable"
          MOV       R4,R2,LSL R3                  ; R4 == Y screen size

          MOV       R1,#4
          SWI       "OS_ReadModeVariable"
          MOV       R8,R2
          MOV       R1,#11
          SWI       "OS_ReadModeVariable"
          MOV       R8,R2,LSL R8                  ; R8 == X screen size

; Set the font colours to black text on light grey background.

          MOV       R1,#1
          MOV       R2,#7
          SWI       "Wimp_SetFontColours"

; Find the outline font that we need.

          ADRL      R1,font_name
          MOV       R2,#192                       ; 12pt wide
          MOV       R3,#192                       ; 12pt high
          MOV       R4,#0
          MOV       R5,#0
          SWI       "XFont_FindFont"
          BVS       service_done

; Work out the maximum line length in points.  This is 300 OS Units less than the current screen
; width.

          SUB       R1,R8,#300
          SWI       "Font_Converttopoints"
          MOV       R9,R1                         ; R9 == Maximum line length in points
          ADRW      R1,block%                     ; R1 -> Fortune string
          MOV       R6,#0                         ; R6 == Longest line lingth so far
          MOV       R7,#0                         ; R7 == Number of rows so far

; Calculate the width and height of the text.  Pass the text to Font_StringWidth and get the
; length of the line that will fit.

.width_loop
          MOV       R2,R9
          MOV       R3,#&FF00
          MOV       R4,#ASC(" ")                  ; Split on space
          MOV       R5,#255
          SWI       "Font_StringWidth"

; If the line is longer than the current maximum, update the current maximum.

          CMP       R2,R6
          MOVGE     R6,R2

; Add 1 to R1 to pass the splitting space and add 1 to R7 to increment the line count.

          ADD       R1,R1,#1
          ADD       R7,R7,#1

; Check the charcter the split was made on.  If it was a contol character, the line end has been
; reached so terminate, otherwise loop again.

          LDRB      R2,[R1,#-1]
          CMP       R2,#32
          BGE       width_loop

; Get the width into OS Units.

          MOV       R1,R6
          SWI       "Font_ConverttoOS"

; Get the box dimensions and plot the box on the screen for the text.

          ADD       R2,R1,#100                    ; R2 == width of box
          MOV       R1,R8,ASR #1                  ; R1 == centre of screen
          MOV       R3,#100                       ; R3 == height of box (100 + 32*lines)
          ADD       R3,R3,R7,ASL #5
          BL        rectangle_plot



          ADRW      R1,block%                     ; R1  -> Fortune text
          MOV       R10,R1                        ; R10 == Backup of pointer
          MOV       R11,R3,ASR #1                 ; R11 == 1/2 height if box
          ADD       R11,R11,#(y_pos%-50-28)       ; R11 == Baseline for first piece of text.

.paint_loop

; Calculate the longest string that will fit in the box. (r! -> Fortune text)

          MOV       R2,R9                         ; R2 == Maximum line length (points)
          MOV       R3,#&FF00                     ; R3 == Maximum line height (points)
          MOV       R4,#ASC(" ")                  ; R4 == Character to split line on
          MOV       R5,#255                       ; R5 == Maximum chars to consider
          SWI       "Font_StringWidth"

          MOV       R7,R1                         ; R7 -> Pointer to end of line

; Work out X coordinate of the start of the line (R2 == Line length in points)

;         MOV       R1,R2                         ; R1 == Length of line (points)
          SWI       "Font_ConverttoOS"
          MOV       R3,R8,ASR #1                  ; R3 == Start of line in OS coordinates
          SUB       R3,R3,R2,ASR #1               ; (R3 = (screen_width/2) - (line_length/2)

; Paint the line of text on the screen (R3 == X position).

          MOV       R1,R10                        ; R1 -> Start of string
          MOV       R10,R7                        ; Save end of string in R10
          MOV       R2,#%1010010000               ; R2 == Plot type flags
          MOV       R4,R11                        ; R4 == Y Position
          MOV       R7,R5                         ; R7 == String length
          MOV       R5,#0
          MOV       R6,#0
          SWI       "Font_Paint"

; Skip past the splitting space in the line and restore R1 and R10 as pointers to the start of
; the next line.

          ADD       R10,R10,#1
          MOV       R1,R10

; Move the Y position down a line (Kludged).

          SUB       R11,R11,#32

; Check the skipped character; if it was <32 (ctrl) then end, otherwise paint the next line.

          LDRB      R2,[R1,#-1]
          CMP       R2,#32
          BGE       paint_loop

; Lose the font.

.end_font_painting
          SWI       "Font_LoseFont"

; Return from the Service Call handler.

.service_done
          LDMFD     R13!,{R0-R12,PC}

; ----------------------------------------------------------------------------------------------------------------------

.close_cookie_file_and_exit

; Close the cookie file and exit without doing anything else.

; => R1 == File handle

          MOV       R0,#0
          SWI       "XOS_Find"
          B         service_done

; ----------------------------------------------------------------------------------------------------------------------

.file_system_variable
          EQUZ      "<Welcome$FortuneFile>"

.cookies_system_variable
          EQUZ      "<Welcome$Fortunes>"

.font_name
          EQUZ      display_font$
          ALIGN

; ----------------------------------------------------------------------------------------------------------------------

.rectangle_plot

; Plot a shadowed rectange on the screen.

; => R1 == Centre of screen
;    R2 == Width of box
;    R3 == Height of box

          STMFD     R13!,{R0-R7,R14}

          MOV       R5,R2,ASR #1                  ; R5 == 1/2 X width
          MOV       R6,R3,ASR #1                  ; R6 == 1/2 Y height
          MOV       R3,R1                         ; R3 == X centre
          MOV       R4,#y_pos%                    ; R4 == Y centre

; Plot the shadow rectangle on the screen in Wimp colour 6.

          MOV       R0,#6
          SWI       "Wimp_SetColour"

          MOV       R0,#4
          SUB       R1,R3,R5
          ADD       R1,R1,#shadow%
          SUB       R2,R4,R6
          SUB       R2,R2,#shadow%
          SWI       "OS_Plot"

          MOV       R0,#101
          ADD       R1,R3,R5
          ADD       R1,R1,#shadow%
          ADD       R2,R4,R6
          SUB       R2,R2,#shadow%
          SWI       "OS_Plot"

; Plot the background rectnagle in Wimp colour 1.

          MOV       R0,#1
          SWI       "Wimp_SetColour"

          MOV       R0,#4
          SUB       R1,R3,R5
          SUB       R2,R4,R6
          SWI       "OS_Plot"

          MOV       R0,#101
          ADD       R1,R3,R5
          ADD       R2,R4,R6
          SWI       "OS_Plot"

; Plot a border rectangle in Wimp colour 7.

          MOV       R0,#7
          SWI       "Wimp_SetColour"

          MOV       R0,#4
          SUB       R1,R3,R5
          SUB       R2,R4,R6
          SWI       "OS_Plot"

          MOV       R0,#5
          ADD       R1,R3,R5
          SUB       R2,R4,R6
          SWI       "OS_Plot"

          MOV       R0,#5
          ADD       R1,R3,R5
          ADD       R2,R4,R6
          SWI       "OS_Plot"

          MOV       R0,#5
          SUB       R1,R3,R5
          ADD       R2,R4,R6
          SWI       "OS_Plot"

          MOV       R0,#5
          SUB       R1,R3,R5
          SUB       R2,R4,R6
          SWI       "OS_Plot"

          LDMFD     R13!,{R0-R7,PC}

; ----------------------------------------------------------------------------------------------------------------------

.read_line

; Read a line from the file to the workspace, stopping on a control character or EOF.
; NB; there is *no* bounds checking on the buffer.

; => R1  == File pointer
;    R12 -> Workspace to store text in

          STMFD     R13!,{R0-R2,R14}

          ADRW      R2,block%                        ; R2 -> Workspace

; Load the file a byte at a time, storing it in the workspace.  Exit if an error occurs or if a
; control character is encountered.

.read_loop
          SWI       "XOS_BGet"
          BVS       read_exit

          MOVCS     R0,#0
          STRB      R0,[R2],#1
          BCS       read_exit

          CMP       R0,#32
          BGE       read_loop

.read_exit
          LDMFD     R13!,{R0-R2,PC}

; ======================================================================================================================
]
IF debug% THEN
[OPT pass%
          FNReportGen
]
ENDIF
NEXT pass%

SYS "OS_File",10,"<Basic$Dir>."+save_as$,&FFA,,code%,code%+P%

END



DEF FNworkspace(RETURN size%,dim%)
LOCAL ptr%
ptr%=size%
size%+=dim%
=ptr%
