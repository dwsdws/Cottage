$NOMOD51
;-----------------------------------------------------------------------------
;  Mull Cottage Control System.
;
;  FILE NAME   :  ALMMON.ASM 
;  DATE        :  5 AUG 2015
;	 VERSION		 :	1.4
;  TARGET MCU  :  C8051F330 
;  DESCRIPTION :  This program monitors doors and windows and sounds
;  								alarm when unauthorised entry detected
; 	NOTES: 19200, 122us delay before RS485TX
;
;-----------------------------------------------------------------------------

$include (c8051f330.inc)                  ; Include register definition file.

;-----------------------------------------------------------------------------
; EQUATES
;-----------------------------------------------------------------------------
;
;REGISTERS 00H TO 07H, STACK POINTER 60H
;RAM 00H TO 07FH (128 BYTES), SFRs 80H TO 0FFH (128 BYTES)
;XRAM 000H TO 1FFH (512 BYTES)
;INTERRUPT VECTOR TABLE 00H TO 033H
;FLASH PROG SPACE 034H TO 1DFFH (7680 BYTES)
;
RS485_EN	EQU P0.1	;RS485 ENABLE : 0 IS RX, 1 IS RX/TX
SDFRT		EQU P1.0	;SIDE DOOR FRONT INTPUT SIGNAL
FRTDR		EQU P0.7	;FRONT DOOR INPUT SIGNAL
FWLFT		EQU P1.3	;FRONT WINDOW LEFT INPUT SIGNAL
FWRHT		EQU P1.2	;FRONT WINDOW RIGHT INPUT SIGNAL
SDROAD	EQU P1.1	;SIDE DOOR ROAD INPUT SIGNAL
ALMSWT 	EQU P1.4	;ALARM SWITCH INPUT SIGNAL
INT_LED EQU P1.7	;INT LED OUTPUT : 1 IS ON
SIREN		EQU P1.5	;SIREEN OUTPUT SIGNAL
BUZER		EQU P1.6	;BIZZER OUTPUT SIGNAL
RED_LED	EQU	P0.0	;RED LED (ALARM) OUTPUT : 1 IS ON
GREEN_LED	EQU P0.6	;GREEN LED (COMMS) OUTPUT : 1 IS ON	
TYPEI		EQU 08BH	;SERVER -> ALMMON MESSAGE TYPE
TYPEO		EQU 08DH	;ALMMON -> SERVER MESSAGE TYPE
STATE		EQU	10H		;ALARM STATE
ALARM		EQU	11H		;ALARM COMMAND FROM SERVER
AFDOOR	EQU	12H		;FRONT DOOR STATUS
ASDRD		EQU	13H		;SIDE DOOR ROAD STATUS
ASDRR		EQU 14H		;SIDE DOOR REAR STATUS
AFWR		EQU	15H		;FRONT WINDOW RIGHT STATUS
AFWL		EQU	16H		;FRONT WINDOW LEFT STATUS
ASTS		EQU	17H		;STATUS
TIME1		EQU	21H		;.5 SEC TIMER COUNT
TIMCTL	EQU	22H		;.5/30/180 SEC TIMER CONTROL
TIMSTS	EQU	23H		;.5/30/180 SEC TIMER STATUS	
SWSTAT	EQU	24H		;INPUT PREVIOUS STATE
CURSWT	EQU	20H		;ALARM INPUT CURRENT SWITCH STATE
RXCNT		EQU	25H		;RX MESSAGE	COUNTER
SOM			EQU 01H		;START OF MESSAGE CHARACTER
EOM			EQU 0CCH	;END OF MESSAGE CHARACTER
BYTCNT	EQU 26H	;RX MESSAGE BYTE COUNT
RXFLG		EQU 27H	;RX MESSAGE FLAG
TXFLG		EQU 28H	;TX MESSAGE FLAG ADDR
SAVR0		EQU 29H	;R0 SAVE (RX INT)
SAVA		EQU	2AH	;ACC SAVE (RX INT)
SAVA30	EQU	31H	;ACC SAVE (30Hz INT)
STCKP		EQU 060H	;STACK POINTER
;
;-----------------------------------------------------------------------------
; RESET and INTERRUPT VECTORS
;-----------------------------------------------------------------------------
	ORG 000H	;RESET VECTOR
;
	AJMP STRT
;
	ORG 023H	;RX COMMS VECTOR
;
	AJMP RXISR	;RX COMMS ISR AT RXISR
;
	ORG 02BH	;TIMER 2 VECTOR
;
	AJMP INT30	;TIMER 2 (30HZ) ISR AT INT30
;
	ORG 080H
;
;-----------------------------------------------------------------------------
; CODE SEGMENT
;-----------------------------------------------------------------------------
;
;*****INITIALISATION*****
;
;****CONFIGURE EXTERNAL PORTS & SET EXTERNAL CLOCK****
;
STRT:	ANL	PCA0MD, #NOT(040H)	;DISABLE WATCHDOG
	ORL	P0SKIP,	#0CH	;P0.2/3 SKIP SINCE XTAL - RESET 00
	ORL P1SKIP, #0H	;RESET 00
	MOV XBR0, #01H		;UART ENABLED FOR P0.4/5 - RESET 00
	MOV	XBR1,	#40H		;CROSSBAR ENABLED - RESET 00
	ANL	P0MDIN,	#NOT(0CH)	;P0.2/3 ANALOG INPUTS - RESET FF		
	ORL P0MDOUT, #43H	;P0.0/1/6 PUSH-PULL - RESET 00
	ORL P1MDOUT, #0E0H	;P1.5/6/7 PUSH-PULL - RESET 00
	ANL P1MDIN, #NOT(00H)	;NO ANALOG I/P - RESET FF
	MOV	OSCXCN,	#67H	;ENABLE EXTERNAL XTAL
	CLR   A						;DELAY 1MS
	DJNZ  ACC, $			;DELAY 340US
	DJNZ  ACC, $			;DELAY 340US
	DJNZ  ACC, $			;DELAY 340US

OSC_WAIT:						; POLL FOR XTLVLD =>1
	MOV	A, OSCXCN
	JNB	ACC.7, OSC_WAIT
	MOV	RSTSRC, #04H	;ENABLE MISSING CLOCK DETECTOR
	MOV	CLKSEL, #01H	;SELECT EXTERNAL CLOCK
	MOV	OSCICN, #00H	;DISABLE INTERNAL OSCILLATOR

	MOV SP, #STCKP	;SET UP STACK POINTER
;
;*****INITIALISE COUNTERS, POINTERS AND FLAGS*****
;
	MOV BYTCNT, #0
	MOV RXFLG, #0		;MESSAGE NOT RX'D
	MOV TXFLG, #0		;NO MESSAGE TX'D
	MOV RXCNT, #0		;RXCNT=0
	CLR SIREN				;SIREEN OFF
	CLR BUZER				;BUZZER OFF
	MOV STATE, #0		;STATE=OFF
	MOV	ALARM, #33H	;ALARM=OFF
	MOV AFDOOR, #33H			;FRONT DOOR
	MOV	ASDRD, #33H			;SIDE DOOR ROAD
	MOV	ASDRR,#33H				;SIDE DOOR REAR
	MOV	AFWR, #33H				;FRONT WINDOW RIGHT
	MOV	AFWL, #33H				;FRONT WINDOW LEFT
	MOV	ASTS, #0H	;STATUS=OFF
	MOV SWSTAT, #0	;SWITCH PREVIOUS STATE = OPEN / OFF
	MOV CURSWT, #0	;CURRENT ALARM INPUT STATE = CLOSED
	MOV	TIMCTL, #0	;.5/30/180 SEC TIMERS OFF
	MOV	TIMSTS, #0	;.5/30/180 SEC TIMERS CLEAR
	MOV TIME1, #0		;CLEAR .5 SEC TIMER COUNT
;	SETB TIMCTL.0	;TEMPORARY TEST
;	SETB TIMCTL.1	;TEMPORARY TEST
	CLR GREEN_LED		;GREEN LED OFF
	CLR RED_LED			;RED LED OFF
	CLR RS485_EN		;ENABLE RS485 RX
	CLR INT_LED			;INT LED OFF
;
;*****CLEAR / INITIALISE REGISTERS*****
;
	MOV R0, #00H
	MOV R1, #00H
	MOV R2, #00H
	MOV R3, #00H
	MOV R4, #00H
	MOV R5, #00H
	MOV R6, #00H
	MOV R7, #00H
	MOV DPH, #0
	MOV DPL, #0
;
;*****CONFIGURE TIMERS*****
;
	MOV PCON, #80H		;SET SMOD
	MOV TMOD, #20H		;8-BIT AUTO RELOAD
	MOV	CKCON,	#02H	;PRESCALE CLOCK BY 48
;
;TIMER 1 - MODE 2 (8-BIT AUTORELOAD)
;BAUDRATE = 22.1184E6/48*(256-TH1)*2
;
;	MOV TH1, #240		;TH1 IS 240 FOR 14400 BAUD
;	MOV TH1, #232		;TH1 IS 232 FOR 9600 BAUD
	MOV TH1, #244		;TH1 IS 244 FOR 19200 BAUD
	ORL TCON, #40H		;TURN ON TIMER 1
;
;TIMER 2 - MODE 16-BIT AUTO RELOAD
;FREQUENCY = 22.1184E6/12*(65536-TH2,TL2) = 30 HZ
	MOV TMR2RLH,	#10H	;RELOAD
	MOV	TMR2RLL,	#00H
	MOV	TMR2H,	#10H	;INITIAL LOAD
	MOV TMR2L,	#00H
	MOV	TMR2CN, #04H	;ENABLE TIMER 2
;
;*****CONFIGURE SERIAL PORT*****
;
	MOV SCON0, #50H		;MODE 1, 8 DATA, 1 STP
;
;*****CONFIGURE / ENABLE INTERRUPTS*****
;
	MOV	IP, #10H		;MAKE RXISR HIGH PRIORITY
	MOV IE, #0B0H		;ENABLE UART AND TIMER 2 INTERRUPTS
;
;*****BACKGROUND TASK*****
;
BGR:	MOV A, RXFLG		;TEST FOR NEW MESSAGE
	CJNE A, #0FFH, NOMSG	;NEW MESSAGE RECEIVED ?
;
;*****PROCESS MESSAGE*****
;
	SETB GREEN_LED
	CLR	IE.4	;DISABLE RS485 INTS
	MOV RXFLG, #0		;CLEAR RXFLG
	ACALL MSGTX	;RESPOND
	CLR GREEN_LED
	SETB	IE.4	;ENABLE RS485 INTS
;
NOMSG:
;*****SERVICE ALARM STATE MACHINE*****
;
	MOV A, STATE	;GET STATE
	CJNE A, #0, NOT0
	CLR BUZER	;OFF(0)
	CLR SIREN
	CLR RED_LED
	MOV ASTS, #0H	;OFF
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #0CCH, A1
	MOV STATE, #1	;SET STATE = TEST (1)
	SJMP STN1
A1:	CJNE A, #55H, A2	;ARMED ?
	MOV STATE, #3	;SET STATE = ARM1 (3)
	SJMP STN1
A2:
	MOV A, CURSWT	;GET ALL SWITCH STATUS
	ANL A, #01FH	;MASK OUT TOP 3 BITS
	JZ STN1
	MOV STATE, #2	;SET STATE = OFF2 (2)
STN1:	AJMP	EASM
NOT0:
	CJNE A, #1, NOT1
	SETB	BUZER	;TEST (1)
	SETB	SIREN
	SETB	RED_LED
	MOV ASTS, #01H	;TEST
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #33H, B1
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1
	SJMP STN1
B1:
	JB CURSWT.5, B2	;CHECK IF OFF BUTTON PRESSED
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	MOV STATE, #8	;SET STATE = OFF3 (8)
	AJMP	EASM
B2:
	SETB	TIMCTL.1	;START 30 SEC TIMER
	JNB	TIMSTS.1, STN1
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	MOV STATE, #8	;SET STATE = OFF3 (8)
	AJMP EASM
NOT1:
	CJNE A, #2, NOT2
	CLR BUZER	;OFF2(2)
	CLR SIREN
	SETB RED_LED
	MOV ASTS, #02H	;OFF
	MOV A, CURSWT	;GET ALL SWITCH STATUS
	ANL A, #01FH	;MASK OUT TOP 3 BITS
	JNZ STN2
	MOV STATE, #0	;SET STATE = OFF (0)
STN2:	AJMP EASM
NOT2:
	CJNE A, #3, NOT3
	CLR SIREN	;ARM1 (3)
	MOV ASTS, #03H	;EN
	SETB	TIMCTL.0	;START .5 SEC TIMER
	SETB	TIMCTL.1	;START 30 SEC TIMER
	JB TIMSTS.0, CX1
	CLR BUZER
	CLR RED_LED
	SJMP CX2
CX1:
	SETB BUZER
	SETB RED_LED
CX2:JNB	TIMSTS.1, CX3
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1
	CLR BUZER
	MOV STATE, #4	;SET STATE = ARM2 (4)
CX3:
	JB CURSWT.5, CX4	;CHECK IF OFF BUTTON PRESSED
	MOV STATE, #8	;SET STATE = OFF3 (8)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1
	CLR TIMCTL.0	;STOP 0.5 SEC TIMER
	SJMP STN3
CX4:
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, STN2
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1
	CLR TIMCTL.0	;STOP 0.5 SEC TIMER
STN3:	AJMP EASM
NOT3:
	CJNE A, #4, NOT4
	MOV ASTS, #04H	;EN
	JB TIMSTS.0, DX1	;ARM2 (4)
	CLR RED_LED
	SJMP DX2
DX1:
	SETB RED_LED
DX2:	MOV A, CURSWT	;GET ALL SWITCH STATUS
	ANL A, #01FH	;MASK OUT TOP 3 BITS
	JZ DX3
	MOV STATE, #5	;SET STATE = ACT1 (5)
	CLR TIMCTL.0
	CLR RED_LED
DX3:
	JB CURSWT.5, DX4	;CHECK IF OFF BUTTON PRESSED
	MOV STATE, #8	;SET STATE = OFF3 (8)
	CLR TIMCTL.0	;STOP 0.5 SEC COUNTER
	SJMP STN3
DX4:
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, STN3
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.0	;STOP 0.5 SEC TIMER
	SJMP STN3
NOT4:
	CJNE A, #5,	NOT5
	MOV ASTS, #05H	;ACT1 (5) - EN
	SETB BUZER
	SETB RED_LED
	SETB TIMCTL.1	;START 30 SEC TIMER
	JNB TIMSTS.1, MEX1
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1	;CLEAR TIMER COUNT
	MOV STATE, #6	;SET STATE = ACT2 (6)
MEX1:
	JB CURSWT.5, MEX2	;CHECK IF OFF BUTTON PRESSED
	MOV STATE, #8	;SET STATE = OFF3 (8)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	AJMP EASM
MEX2:
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, EASM
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	AJMP EASM
NOT5:
	CJNE A, #6, NOT6
	SETB BUZER	;ACT2 (6)
	SETB RED_LED
	SETB	SIREN
	MOV ASTS, #06H	;ON
	SETB TIMCTL.1	;START 30 SEC TIMER
	JNB TIMSTS.1, GX1
	CLR TIMCTL.1	;STOP 30 SEC COUNTER
	MOV STATE, #7	;SET STATE = ACT3 (7)
GX1:
	JB CURSWT.5, GX2	;CHECK IF OFF BUTTON PRESSED
	MOV STATE, #8	;SET STATE = OFF3 (8)
	CLR TIMCTL.1	;STOP 30 SEC COUNTER
	CLR TIMSTS.1
	SJMP EASM
GX2:
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, EASM
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.1	;STOP 30 SEC TIMER
	CLR TIMSTS.1
	SJMP EASM
NOT6:
	CJNE A, #7, NOT7
	CLR SIREN	;ACT3 (7)
	CLR BUZER
	MOV ASTS, #07H	;ON
	SETB	TIMCTL.0	;START .5 SEC TIMER
	JB TIMSTS.0, FX1
	CLR RED_LED
	SJMP FX2
FX1:
	SETB RED_LED
FX2:
	JB CURSWT.5, FX3	;CHECK IF OFF BUTTON PRESSED
	MOV STATE, #8	;SET STATE = OFF3 (8)
	CLR TIMCTL.0	;STOP 0.5 SEC COUNTER
	SJMP EASM
FX3:
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, EASM
	MOV STATE, #0	;SET STATE = OFF (0)
	CLR TIMCTL.0	;STOP 0.5 SEC TIMER
	SJMP EASM
NOT7:
	CJNE A, #8, EASM
	CLR SIREN	;OFF3 (8)
	CLR BUZER
	CLR RED_LED
	MOV ASTS, #08H	;OFF
	MOV A, ALARM	;CHECK COMMAND
	CJNE A, #033H, EASM
	MOV STATE, #0	;SET STATE = OFF (0)

EASM:
	JMP BGR
;
;*****RX SERIAL COMMS ISR*****
;
RXISR:
	MOV	SAVA,	A
	PUSH  PSW	;SAVE REGS
;	PUSH  ACC
	MOV SAVR0, R0		;SAVE R0
;	SETB GREEN_LED
;
	CLR SCON0.0		;CLEAR RI FLAG
	MOV A, BYTCNT		;GET BYTE COUNT
	CJNE A, #0, DD1		;NEW MESSAGE ?
;
;NEW MESSAGE
;
	MOV R2, SBUF0		;READ BYTE
	CJNE R2, #SOM, AA2	;ABORT IF NOT SOM (01H)
	CLR A			;INITIALISE CHECKSUM
	XRL A, R2		;UPDATE CHECKSUM
	MOV R4, A		;SAVE CHECKSUM
	MOV BYTCNT, #2		;INITIALISE BYTE COUNT
	AJMP END11		;EXIT ROUTINE
AA2:	
;	SETB RED_LED
	AJMP END21		;ABORT MESSAGE
;
DD1:	MOV A, BYTCNT		;EXISTING MESSAGE, GET BYTE COUNT
	CJNE A, #2, DD2		;BYTE 2 ?
;
	MOV R2, SBUF0		;YES, GET TYPE
	MOV A, BYTCNT		;INC BYTE COUNT
	INC A
	MOV BYTCNT, A
	MOV A, R4		;UPDATE CHECKSUM
	XRL A, R2
	MOV R4, A
	MOV A, R2		;GET SOURCE
	CJNE A, #TYPEI, AA2	;MSG TYPE = TYPEI (8EBH) ?
	AJMP END11		;EXIT ROUTINE
;
DD2:	CJNE A, #3, DD3		;BYTE 3 ?
	MOV R2, SBUF0					;YES GET ALARM
	MOV A, R2
	MOV ALARM, A					;SAVE ALARM
	MOV A, BYTCNT					;INC BYTE COUNT
	INC A
	MOV BYTCNT, A
	MOV A, R4								;UPDATE CHECKSUM
	XRL A, R2
	MOV R4, A
	AJMP END11		;EXIT ROUTINE
;
DD3:	CJNE A, #4, DD4		;BYTE 4 ?
	MOV A, R4
	CJNE A, SBUF0, END21	;IF CHECKSUM BAD ABORT MESSAGE
	MOV A, BYTCNT		;GOOD - INC BYTE COUNT
	INC A
	MOV BYTCNT, A
	AJMP END11		;EXIT ROUTINE
;
DD4:	CJNE A, #5, DD5		;BYTE 5 ?
	MOV A, R4		;READ CHECKSUM
	CPL A			;COMPLEMENT CHECKSUM
	CJNE A, SBUF0, END21	;IF *CHECKSUM BAD ABORT MESSAGE
	MOV A, BYTCNT		;GOOD - INC BYTE COUNT
	INC A
	MOV BYTCNT, A
	AJMP END11		;EXIT ROUTINE
;
DD5:	MOV A, SBUF0		;READ BYTE 6
	CJNE A, #EOM, END21	;IF NOT EOM ABORT MESSAGE
;
;*****MESSAGE COMPLETE AND ERROR FREE*****
;
	MOV RXFLG, #0FFH	;SET RX MESSAGE FLAG
	INC RXCNT		;INC RX COUNTER
;	CLR RED_LED
;
END21:	MOV BYTCNT, #0		;CLEAR BYTE COUNT
	MOV R4, #0		;CLEAR CHECKSUM
;
END11:
	POP  PSW	;RESTORE REGS
;	POP  ACC
	MOV	A, SAVA
	MOV R0, SAVR0		;RESTORE R0
;	CLR GREEN_LED
	RETI
;
;*****30HZ INT*****
;
INT30:
	PUSH PSW	;SAVE REGS
;	PUSH ACC
	MOV SAVA30, A	;SAVE ACCUMULATOR
	CLR TMR2CN.7	;CLEAR INT FLAG
	CPL INT_LED
;	
;****500MS TIMER***
	JNB TIMCTL.0, NXT1
	INC TIME1
	JNB TIME1.3, NXTTMR
	MOV TIME1, #0
	CPL TIMSTS.0
;	CPL RED_LED	;TEMPORARY TEST
;	CPL BUZER		;TEMPORARY TEST
	JMP NXTTMR
NXT1:
	CLR TIMSTS.0
	MOV TIME1, #0
;END 500MS TIMER
;
;****36SEC / 180SEC TIMER***
NXTTMR:
	JNB TIMCTL.1, NXT2
	INC DPTR
	MOV A, DPH
	CJNE A,#04H, MOVEON	;MIN = 9 SEC ie 1=9SEC
	MOV DPH, #0
	MOV DPL, #0
	CPL TIMSTS.1
;	CPL RED_LED	;TEMPORARY TEST
;	CPL BUZER		;TEMPORARY TEST
	JMP MOVEON
NXT2:
	CLR TIMSTS.1
	MOV DPH, #0
	MOV DPL, #0
;END 36SEC / 180SEC TIMER	
;
;****FRONT DOOR STATE****
;
MOVEON:
	JNB FRTDR, JUM01			;CURRENTLY OPEN ?
	JNB SWSTAT.0, JUM02	;PREVIOUSLY OPEN ?
	MOV AFDOOR, #0AAH		;=OPEN
	SETB CURSWT.0				;=OPEN
	JMP JNXT1
JUM01:
	JB SWSTAT.0, JUM03		;PREVIOUSLY CLOSED ?
	MOV AFDOOR, #33H		;=CLOSED
	CLR CURSWT.0				;CLOSED
	JMP JNXT1
JUM02:
	SETB SWSTAT.0				;SET PREVIOUSLY OPEN
	JMP JNXT1
JUM03:
	CLR SWSTAT.0				;SET PREVIOUSLY CLOSED
;	
JNXT1:
;
;****SIDE DOOR (ROAD) STATE****
;
	JNB SDROAD, JUM11			;CURRENTLY OPEN ?
	JNB SWSTAT.1, JUM12	;PREVIOUSLY OPEN ?
	MOV ASDRD, #0AAH		;=OPEN
	SETB CURSWT.1				;OPEN
	JMP JNXT2
JUM11:
	JB SWSTAT.1, JUM13		;PREVIOUSLY CLOSED ?
	MOV ASDRD, #33H		;=CLOSED
	CLR CURSWT.1			;=CLOSED
	JMP JNXT2
JUM12:
	SETB SWSTAT.1				;SET PREVIOUSLY OPEN
	JMP JNXT2
JUM13:
	CLR SWSTAT.1				;SET PREVIOUSLY CLOSED
;	
JNXT2:
;
;****SIDE DOOR (REAR) STATE****
;
	JNB SDFRT, JUM21			;CURRENTLY OPEN ?
	JNB SWSTAT.2, JUM22	;PREVIOUSLY OPEN ?
	MOV ASDRR, #0AAH		;=OPEN
	SETB CURSWT.2				;=OPEN
	JMP JNXT3
JUM21:
	JB SWSTAT.2, JUM23		;PREVIOUSLY CLOSED ?
	MOV ASDRR, #33H		;=CLOSED
	CLR CURSWT.2			;=CLOSED
	JMP JNXT3
JUM22:
	SETB SWSTAT.2				;SET PREVIOUSLY OPEN
	JMP JNXT3
JUM23:
	CLR SWSTAT.2				;SET PREVIOUSLY CLOSED
;	
JNXT3:
;
;****FRONT WINDOW (RIGHT) STATE****
;
	JNB FWRHT, JUM31			;CURRENTLY OPEN ?
	JNB SWSTAT.3, JUM32	;PREVIOUSLY OPEN ?
	MOV AFWR, #0AAH		;=OPEN
	SETB CURSWT.3			;=OPEN
	JMP JNXT4
JUM31:
	JB SWSTAT.3, JUM33		;PREVIOUSLY CLOSED ?
	MOV AFWR, #33H		;=CLOSED
	CLR CURSWT.3			;=CLOSED
	JMP JNXT4
JUM32:
	SETB SWSTAT.3				;SET PREVIOUSLY OPEN
	JMP JNXT4
JUM33:
	CLR SWSTAT.3				;SET PREVIOUSLY CLOSED
;	
JNXT4:
;
;****FRONT WINDOW (LEFT) STATE****
;
	JNB FWLFT, JUM41			;CURRENTLY OPEN ?
	JNB SWSTAT.4, JUM42	;PREVIOUSLY OPEN ?
	MOV AFWL, #0AAH		;=OPEN
	SETB	CURSWT.4		;=OPEN
	JMP JNXT5
JUM41:
	JB SWSTAT.4, JUM43		;PREVIOUSLY CLOSED ?
	MOV AFWL, #33H		;=CLOSED
	CLR CURSWT.4			;=CLOSED
	JMP JNXT5
JUM42:
	SETB SWSTAT.4				;SET PREVIOUSLY OPEN
	JMP JNXT5
JUM43:
	CLR SWSTAT.4				;SET PREVIOUSLY CLOSED
;	
JNXT5:
;
;****ON/OFF SWITCH STATE****
;
	JNB ALMSWT, JUM51			;CURRENTLY OPEN (OFF) ?
	JNB SWSTAT.5, JUM52	;PREVIOUSLY OPEN (OFF) ?
	SETB	CURSWT.5		;=OPEN (OFF)
	JMP JFIN
JUM51:
	JB SWSTAT.5, JUM53		;PREVIOUSLY CLOSED (ON) ?
	CLR CURSWT.5		;=CLOSED (ON)
	JMP JFIN
JUM52:
	SETB SWSTAT.5				;SET PREVIOUSLY OPEN (OFF)
	JMP JFIN
JUM53:
	CLR SWSTAT.5				;SET PREVIOUSLY CLOSED (ON)
;	
JFIN:

;	POP ACC
	MOV A, SAVA30	;RESTORE ACCUMULATOR
	POP PSW
	RETI
;
;*****SUBROUTINE TO TRANSMIT MESSAGE TO SERVER*****
;
MSGTX:	
	
;***DELAY 122us BEFORE ENABLE RS485TX***
	
	MOV R1, #080H
DELAY:	INC R1
	MUL AB
	MUL AB
	MUL AB
	MUL AB
	CJNE R1,#0FFH, DELAY

;**********************

	SETB RS485_EN	;ENABLE RS485 TX
	MOV R1, #00H		;CLEAR CHKSUM
;
	MOV SBUF0, #SOM		;TX SOM (01H)
	MOV A, R1		;UPDATE CHKSUM
	XRL A, #SOM
	MOV R1, A
	ACALL TXTST
;	
	MOV SBUF0, #TYPEO	;MESSAGE TYPE
	MOV A, R1		;UPDATE CHKSUM
	XRL A, #TYPEO
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, ASTS		;ALARM STATUS
	MOV A, R1		;UPDATE CHKSUM
	XRL A, ASTS
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, AFDOOR		;FRONT DOOR
	MOV A, R1		;UPDATE CHKSUM
	XRL A, AFDOOR
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, ASDRD	;SIDE DOOR ROAD
	MOV A, R1		;UPDATE CHKSUM
	XRL A, ASDRD
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, ASDRR	;SIDE DOOR REAR
	MOV A, R1		;UPDATE CHKSUM
	XRL A, ASDRR
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, AFWR	;FRONT WINDOW RIGHT
	MOV A, R1		;UPDATE CHKSUM
	XRL A, AFWR
	MOV R1, A
	ACALL TXTST
;
	MOV SBUF0, AFWL	;FRONT WINDOW LEFT
	MOV A, R1		;UPDATE CHKSUM
	XRL A, AFWL
	MOV R1, A
	ACALL TXTST
;
	MOV A, R1		;GET CHECKSUM
	MOV SBUF0, A		;CHECKSUM
	ACALL TXTST
;
	MOV A, R1		;GET CHECKSUM
	CPL A			;COMPLEMENT CHECKSUM
	MOV SBUF0, A		;*CHKSUM
	ACALL TXTST
;
	MOV SBUF0, #EOM		;EOM (CCH)
	ACALL TXTST
;
	CLR RS485_EN		;SWITCH OFF TX
	RET
;
;*****SUBROUTINE TO TEST TI BIT*****
;
TXTST:	JNB SCON0.1, TXTST	;TEST TI BIT
	CLR SCON0.1		;CLEAR TI BIT
	RET
;
;
;End of File
	END
