; Copyright 1997-2013, Stephen Fryatt (info@stevefryatt.org.uk)
;
; This file is part of Fortune:
;
;   http://www.stevefryatt.org.uk/software/
;
; Licensed under the EUPL, Version 1.1 only (the "Licence");
; You may not use this work except in compliance with the
; Licence.
;
; You may obtain a copy of the Licence at:
;
;   http://joinup.ec.europa.eu/software/page/eupl
;
; Unless required by applicable law or agreed to in
; writing, software distributed under the Licence is
; distributed on an "AS IS" basis, WITHOUT WARRANTIES
; OR CONDITIONS OF ANY KIND, either express or implied.
;
; See the Licence for the specific language governing
; permissions and limitations under the Licence.

; Fortune.s
;
; Fortune Module Source
;
; 26/32 bit neutral

;version$="1.10"
;save_as$="Fortune"

XOS_BGet				EQU	&02000A
XOS_Byte				EQU	&020006
XOS_CallEvery				EQU	&02003C
XOS_Claim				EQU	&02001F
XOS_ConvertCardinal4			EQU	&0200D8
XOS_ConvertHex4				EQU	&0200D2
XOS_File				EQU	&020008
XOS_Find				EQU	&02000D
XOS_GSTrans				EQU	&020027
XOS_Module				EQU	&02001E
XOS_NewLine				EQU	&020003
XOS_PrettyPrint				EQU	&020044
XOS_ReadArgs				EQU	&020049
XOS_ReadUnsigned			EQU	&020021
XOS_ReadVarVal				EQU	&020023
XOS_Release				EQU	&020020
XOS_RemoveTickerEvent			EQU	&02003D
XOS_SpriteOp				EQU	&02002E
XOS_Word				EQU	&020007
XOS_Write0				EQU	&020002
XOS_WriteC				EQU	&020000
XOS_WriteS				EQU	&020001
XFilter_DeRegisterPostFilter		EQU	&062643
XFilter_RegisterPostFilter		EQU	&062641
XFont_FindFont				EQU	&060081
XResourceFS_RegisterFiles		EQU	&061B40
XResourceFS_DeregisterFiles		EQU	&061B41
XTaskManager_EnumerateTasks		EQU	&062681
XTerritory_UpperCaseTable		EQU	&063058
XWimp_CloseDown				EQU	&0600DD
XWimp_GetCaretPosition			EQU	&0600D3
XWimp_GetWindowInfo			EQU	&0600CC
XWimp_Initialise			EQU	&0600C0
XWimp_Poll				EQU	&0600C7
XWimp_ReadSysInfo			EQU	&0600F2

OS_Exit					EQU	&000011
OS_GenerateError			EQU	&00002B

OS_Plot					EQU	&000045
OS_ReadModeVariable			EQU	&000035
Font_ConverttoOS			EQU	&040088
Font_Converttopoints			EQU	&040089
Font_LoseFont				EQU	&040082
Font_Paint				EQU	&040086
Font_StringWidth			EQU	&040085
Wimp_SetColour				EQU	&0400E6
Wimp_SetFontColours			EQU	&0400F3


; ---------------------------------------------------------------------------------------------------------------------
; Set up the Module Workspace

WS_BlockSize		*	256

			^	0
WS_Block		#	WS_BlockSize

WS_Size			*	@

; ---------------------------------------------------------------------------------------------------------------------

ShadowSize		EQU	8
YPosition		EQU	180

; ======================================================================================================================
; Module Header

	AREA	Module,CODE,READONLY
	ENTRY

ModuleHeader
	DCD	0				; Offset to task code
	DCD	InitCode			; Offset to initialisation code
	DCD	FinalCode			; Offset to finalisation code
	DCD	ServiceCode			; Offset to service-call handler
	DCD	TitleString			; Offset to title string
	DCD	HelpString			; Offset to help string
	DCD	0				; Offset to command table
	DCD	0				; SWI Chunk number
	DCD	0				; Offset to SWI handler code
	DCD	0				; Offset to SWI decoding table
	DCD	0				; Offset to SWI decoding code
	DCD	0				; MessageTrans file
	DCD	ModuleFlags			; Offset to module flags

; ======================================================================================================================

ModuleFlags
	DCD	1				; 32-bit compatible

; ======================================================================================================================

TitleString
	DCB	"Fortune",0

HelpString
	DCB	"Fortune Cookie",9,$BuildVersion," (",$BuildDate,") ",169," Stephen Fryatt, 1997",0	;-",$BuildDate:RIGHT:4,0
	ALIGN

; ======================================================================================================================

InitCode

; Initialisation code

	STMFD	R13!,{R0-R11,R14}

; Check that the module hasn't already initialised (ie workspace pointer == 0)

	LDR	R0,[R12]
	TEQ	R0,#0
	BNE	InitExit

; Claim 256 bytes of workspace.

	MOV	R0,#6
	MOV	R3,#WS_Size
	SWI	XOS_Module
	BVS	InitExit

	STR	R2,[R12]

InitExit
	LDMFD	R13!,{R0-R11,PC}

; ======================================================================================================================

FinalCode

; Finalisation code.

; See if the finalisation is fatal; if not, don't do anything.

	TEQ	R10,#0
	MOVEQ	PC,R14

	STMFD	R13!,{R14}

; Release the workspace and set the workspace pointer to zero.

	MOV	R0,#7
	LDR	R2,[R12]
	SWI	XOS_Module
	BVS	FinalExit

	MOV	R0,#0
	STR	R0,[R12]

FinalExit
	LDMFD	R13!,{PC}

; ======================================================================================================================

ServiceCode

; The service call handler

; We only want Service_DesktopWelcome (&7C) so discard all others.

	TEQ	R1,#&7C
	MOVNE	PC,R14

DesktopWelcome

; Now we know that it is Service_DesktopWelcome, so set up registers and start on the banner.

	STMFD	R13!,{R0-R12,R14}

	LDR	R12,[R12]				; R12 -> Workspace

OpenCookieFile

	ADD	R1,R12,#WS_Block			; R1 -> Workspace block

; Use OS_GSTrans to evaluate <Welcome$FortuneFile> into the workspace.  The code is exited if
; the variable is unset or dues not exist.

	ADR	R0,FileSystemVariable
	MOV	R2,#255
	SWI	XOS_GSTrans
	BVS	ServiceDone

	TEQ	R2,#0
	BEQ	ServiceDone

; Open the cookie file, putting the handle in R0.  Exit if the file does not exist.

	MOV	R0,#&4F
	SWI	XOS_Find
	BVS	ServiceDone

	TEQ	R0,#0
	BEQ	ServiceDone

	MOV	R7,R0					; R7 == File handle

; Use OS_GSTrans to read in <Welcome$Fortunes>, the number of fortunes in the file.

	ADRL	R0,CookiesSystemVariable
	MOV	R2,#255
	SWI	XOS_GSTrans
	BVS	CloseCookieFileAndExit

	TEQ	R2,#0
	BEQ	CloseCookieFileAndExit

; Convert the number of fortunes from a string to a number.

	MOV	R0,#10					; Base 10
	SWI	XOS_ReadUnsigned
	BVS	CloseCookieFileAndExit

	MOV	R4,R2					; R4 == Number of cookies

; Load the RTC into the workspace, pointed to by R1

	MOV	R0,#14
	ADD	R1,R12,#WS_Block
	MOV	R3,#3
	STRB	R3,[R1]
	SWI	XOS_Word
	BVS	CloseCookieFileAndExit

; Calculate into R5 the minimum number of bits needed to store the number of cookies.  This is
; used as the number of bits we need to take from the RTC value.

	MOV	R5,#1					; R5 == Bit counter
	MOV	R6,#1					; R6 == Maximum value with this R5 bits

BitSizeTooSmall
	CMP	R4,R6
	BLE	BitSizeOK
	ORR	R6,R6,R6,LSL #1
	ADD	R5,R5,#1
	B	BitSizeTooSmall

; Now that R5 contains the number of bits needed, subtract from 31 to give the number of bits not
; needed from the RTC.  These bits are then zeroed by shifting them out of the register.

BitSizeOK
	RSB	R5,R5,#32

	LDR	R3,[R1]					; R3 == LSBs of RTC
	MOV	R3,R3,LSL R5
	MOV	R3,R3,LSR R5

; Bring the number into range by subtracting the number of cookies if necessary.

NumberTooBig
	CMP	R3,R4
	BLE	NumberOK
	SUB	R3,R3,R4
	B	NumberTooBig

; Finally make sure that the cookie number isn't 0 and set the filehandle up for OS_BGet.

NumberOK
	TEQ	R3,#0
	MOVEQ	R3,#1

	MOV	R1,R7					; R1 == File handle

; Read through the file line by line until the correct cookie is stored in the workspace buffer.

EnumCookies
	BL	ReadLine
	BVS	CloseCookieFileAndExit
	SUBS	R3,R3,#1
	BNE	EnumCookies

; Close the cookie file once the fortune is in the buffer.

CloseCookieFile
	MOV	R0,#0
	SWI	XOS_Find
	BVS	ServiceDone

; Read the size of the screen at the start of the Desktop.

GetScreenModeDetails
	MOV	R0,#-1					; Current screen mode

	MOV	R1,#5
	SWI	OS_ReadModeVariable
	MOV	R3,R2
	MOV	R1,#12
	SWI	OS_ReadModeVariable
	MOV	R4,R2,LSL R3				; R4 == Y screen size

	MOV	R1,#4
	SWI	OS_ReadModeVariable
	MOV	R8,R2
	MOV	R1,#11
	SWI	OS_ReadModeVariable
	MOV	R8,R2,LSL R8				; R8 == X screen size

; Set the font colours to black text on light grey background.

	MOV	R1,#1
	MOV	R2,#7
	SWI	Wimp_SetFontColours

; Find the outline font that we need.

	ADRL	R1,FontName
	MOV	R2,#192					; 12pt wide
	MOV	R3,#192					; 12pt high
	MOV	R4,#0
	MOV	R5,#0
	SWI	XFont_FindFont
	BVS	ServiceDone

; Work out the maximum line length in points.  This is 300 OS Units less than the current screen
; width.

	SUB	R1,R8,#300
	SWI	Font_Converttopoints
	MOV	R9,R1					; R9 == Maximum line length in points
	ADD	R1,R12,#WS_Block			; R1 -> Fortune string
	MOV	R6,#0					; R6 == Longest line lingth so far
	MOV	R7,#0					; R7 == Number of rows so far

; Calculate the width and height of the text.  Pass the text to Font_StringWidth and get the
; length of the line that will fit.

WidthLoop
	MOV	R2,R9
	MOV	R3,#&FF00
	MOV	R4,#" "					; Split on space
	MOV	R5,#255
	SWI	Font_StringWidth

; If the line is longer than the current maximum, update the current maximum.

	CMP	R2,R6
	MOVGE	R6,R2

; Add 1 to R1 to pass the splitting space and add 1 to R7 to increment the line count.

	ADD	R1,R1,#1
	ADD	R7,R7,#1

; Check the charcter the split was made on.  If it was a contol character, the line end has been
; reached so terminate, otherwise loop again.

	LDRB	R2,[R1,#-1]
	CMP	R2,#32
	BGE	WidthLoop

; Get the width into OS Units.

	MOV	R1,R6
	SWI	Font_ConverttoOS

; Get the box dimensions and plot the box on the screen for the text.

	ADD	R2,R1,#100				; R2 == width of box
	MOV	R1,R8,ASR #1				; R1 == centre of screen
	MOV	R3,#100					; R3 == height of box (100 + 32*lines)
	ADD	R3,R3,R7,ASL #5
	BL	RectanglePlot

	ADD	R1,R12,#WS_Block			; R1  -> Fortune text
	MOV	R10,R1					; R10 == Backup of pointer
	MOV	R11,R3,ASR #1				; R11 == 1/2 height if box
	ADD	R11,R11,#(YPosition-50-28)		; R11 == Baseline for first piece of text.

PaintLoop

; Calculate the longest string that will fit in the box. (r! -> Fortune text)

	MOV	R2,R9					; R2 == Maximum line length (points)
	MOV	R3,#&FF00				; R3 == Maximum line height (points)
	MOV	R4,#" "					; R4 == Character to split line on
	MOV	R5,#255					; R5 == Maximum chars to consider
	SWI	Font_StringWidth

	MOV	R7,R1					; R7 -> Pointer to end of line

; Work out X coordinate of the start of the line (R2 == Line length in points)

;	MOV	R1,R2					; R1 == Length of line (points)
	SWI	Font_ConverttoOS
	MOV	R3,R8,ASR #1				; R3 == Start of line in OS coordinates
	SUB	R3,R3,R2,ASR #1			; (R3 = (screen_width/2) - (line_length/2)

; Paint the line of text on the screen (R3 == X position).

	MOV	R1,R10					; R1 -> Start of string
	MOV	R10,R7					; Save end of string in R10
	MOV	R2,#2_1010010000				; R2 == Plot type flags
	MOV	R4,R11					; R4 == Y Position
	MOV	R7,R5					; R7 == String length
	MOV	R5,#0
	MOV	R6,#0
	SWI	Font_Paint

; Skip past the splitting space in the line and restore R1 and R10 as pointers to the start of
; the next line.

	ADD	R10,R10,#1
	MOV	R1,R10

; Move the Y position down a line (Kludged).

	SUB	R11,R11,#32

; Check the skipped character; if it was <32 (ctrl) then end, otherwise paint the next line.

	LDRB	R2,[R1,#-1]
	CMP	R2,#32
	BGE	PaintLoop

; Lose the font.

EndFontPainting
	SWI	Font_LoseFont

; Return from the Service Call handler.

ServiceDone
	LDMFD	R13!,{R0-R12,PC}

; ----------------------------------------------------------------------------------------------------------------------

CloseCookieFileAndExit

; Close the cookie file and exit without doing anything else.

; => R1 == File handle

	MOV	R0,#0
	SWI	XOS_Find
	B	ServiceDone

; ----------------------------------------------------------------------------------------------------------------------

FileSystemVariable
	DCB	"<Welcome$FortuneFile>",0

CookiesSystemVariable
	DCB	"<Welcome$Fortunes>",0

FontName
	DCB	"Trinity.Bold",0
	ALIGN

; ----------------------------------------------------------------------------------------------------------------------

RectanglePlot

; Plot a shadowed rectange on the screen.

; => R1 == Centre of screen
;    R2 == Width of box
;    R3 == Height of box

	STMFD	R13!,{R0-R7,R14}

	MOV	R5,R2,ASR #1				; R5 == 1/2 X width
	MOV	R6,R3,ASR #1				; R6 == 1/2 Y height
	MOV	R3,R1					; R3 == X centre
	MOV	R4,#YPosition				; R4 == Y centre

; Plot the shadow rectangle on the screen in Wimp colour 6.

	MOV	R0,#6
	SWI	Wimp_SetColour

	MOV	R0,#4
	SUB	R1,R3,R5
	ADD	R1,R1,#ShadowSize
	SUB	R2,R4,R6
	SUB	R2,R2,#ShadowSize
	SWI	OS_Plot

	MOV	R0,#101
	ADD	R1,R3,R5
	ADD	R1,R1,#ShadowSize
	ADD	R2,R4,R6
	SUB	R2,R2,#ShadowSize
	SWI	OS_Plot

; Plot the background rectnagle in Wimp colour 1.

	MOV	R0,#1
	SWI	Wimp_SetColour

	MOV	R0,#4
	SUB	R1,R3,R5
	SUB	R2,R4,R6
	SWI	OS_Plot

	MOV	R0,#101
	ADD	R1,R3,R5
	ADD	R2,R4,R6
	SWI	OS_Plot

; Plot a border rectangle in Wimp colour 7.

	MOV	R0,#7
	SWI	Wimp_SetColour

	MOV	R0,#4
	SUB	R1,R3,R5
	SUB	R2,R4,R6
	SWI	OS_Plot

	MOV	R0,#5
	ADD	R1,R3,R5
	SUB	R2,R4,R6
	SWI	OS_Plot

	MOV	R0,#5
	ADD	R1,R3,R5
	ADD	R2,R4,R6
	SWI	OS_Plot

	MOV	R0,#5
	SUB	R1,R3,R5
	ADD	R2,R4,R6
	SWI	OS_Plot

	MOV	R0,#5
	SUB	R1,R3,R5
	SUB	R2,R4,R6
	SWI	OS_Plot

	LDMFD	R13!,{R0-R7,PC}

; ----------------------------------------------------------------------------------------------------------------------

ReadLine

; Read a line from the file to the workspace, stopping on a control character or EOF.
; NB; there is *no* bounds checking on the buffer.

; => R1  == File pointer
;    R12 -> Workspace to store text in

	STMFD	R13!,{R0-R2,R14}

	ADD	R2,R12,#WS_Block			; R2 -> Workspace

; Load the file a byte at a time, storing it in the workspace.  Exit if an error occurs or if a
; control character is encountered.

ReadLoop
	SWI	XOS_BGet
	BVS	ReadExit

	MOVCS	R0,#0
	STRB	R0,[R2],#1
	BCS	ReadExit

	CMP	R0,#32
	BGE	ReadLoop

ReadExit
	LDMFD	R13!,{R0-R2,PC}

; ======================================================================================================================

	END
