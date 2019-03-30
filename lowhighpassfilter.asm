###
## Low/High-pass filter for .bmp files
## Kamil Zacharczuk, 11/2018
## Projekt na laboratoria z Architektury Komputera, 'duzy MIPS'
## WEiTI PW, 3. semestr
###
			.data

lpf:			.byte		1,1,1,1,1,1,1,1,1
hpf:			.byte		0,-1,0,-1,5,-1,0,-1,0

msg_intro:		.asciiz		"\nHigh/Low-Pass Filter for .bmp files\nKamil Zacharczuk, 11/2018\n-------------------------\n"
msg_inputfile:		.asciiz		"Input file path: "
msg_outputfile:		.asciiz		"Output file path: "
msg_choosefilter:	.asciiz		"Choose the filter.\n1 - high-pass, any other integer - low-pass: "
msg_inputfile_err:	.asciiz		"Input file not found.\n"
msg_outputfile_err:	.asciiz		"Output file problem.\n"
msg_wronginput:		.asciiz		"Wrong input!\n"
msg_done:		.asciiz		"Done.\n"

in_buffer:		.space		65536	# pixel data read from the input file at once
out_buffer:		.space		65536	# pixel data written to the output file at once
buf_inputfile:		.space 		64
buf_outputfile:		.space		64
header:			.space		36
useless_header:		.space		64 	# useless header info, probably 54-(header) bytes (I'm reserving more though)

offset_buf:		.space		4	# buffer to reserve space in register s2
width_buf:		.space		2	# buffer to reserve space in register s3
size_buf:		.space		4	# buffer to reserve space in register s4

####   global variables
# s0 - filter mask
# s1 - input file descriptor
# s2 - pixel array start offset
# s3 - image width
# s4 - image height
# s5 - output file descriptor
# s6 - output buffer address

			.text
main:
#####################
## get files names

		# display intro
		li $v0, 4
		la $a0, msg_intro
		syscall
		
		# get input file name
		li $v0, 4
		la $a0, msg_inputfile
		syscall
		
		li $v0, 8
		la $a0, buf_inputfile
		li $a1, 64
		syscall
		
		# get output file name
		li $v0, 4
		la $a0, msg_outputfile
		syscall
		
		li $v0, 8
		la $a0, buf_outputfile
		li $a1, 64
		syscall
		
		
###############################
## delete '\n' from file names
		li $t1, -1	
inputfile_newline_remove:
		beq $t1, 64, removed_from_input
		addiu $t1, $t1, 1
		lb $t2, buf_inputfile($t1)
		bne $t2, '\n', inputfile_newline_remove
		sb $zero, buf_inputfile($t1)
removed_from_input:
		li $t1, -1
outputfile_newline_remove:
		beq $t1, 64, open_input_file
		addiu $t1, $t1, 1
		lb $t2, buf_outputfile($t1)
		bne $t2, '\n', outputfile_newline_remove
		sb $zero, buf_outputfile($t1)

##################################
## opening files
open_input_file:
		# open input file
		li $v0, 13
		la $a0, buf_inputfile
		li $a1, 0		# flag 0 == read mode
		li $a2, 0
		syscall	
		
		# save the descriptor if the file has been found
		bltz $v0, input_file_err
		move $s1, $v0 
		
		# read header
		li $v0, 14
		move $a0, $s1 		# copy the descriptor
		la $a1, header
		li $a2, 36 		# header's useful information size
		syscall
		
		# save useful info
		la $t0, header
		lwr $s2, 10($t0)	# offset at which pixel array begins
		lwr $s3, 18($t0)	# image width	
		lwr $s4, 22($t0)	# image height

		# read the rest of the header, which is not useful
		subiu $t1, $s2, 36 	# its size is (pixel array start offset) - (useful info size)
		
		li $v0, 14
		move $a0, $s1 
		la $a1, useless_header
		move $a2, $t1
		syscall
		
open_output_file:
		li $v0, 13
		la $a0, buf_outputfile
		li $a1, 1 		# flag 1 == write mode
		li $a2, 0
		syscall
		
		# save the descriptor if the file has been found		
		bltz $v0, output_file_err
		move $s5, $v0
		
		# write header info to the output file
		li $v0, 15
		move $a0, $s5
		la $a1, header
		li $a2, 36
		syscall
		
		li $v0, 15
		move $a0, $s5
		la $a1, useless_header
		move $a2, $t1
		syscall
		
##############################
## choosing filter
choose_filter_type:
		li $v0, 4
		la $a0, msg_choosefilter
		syscall
		
		li $v0, 5
		syscall
		
		la $s0, lpf
		bne $v0, 1, filter_it	# if chosen lpf, the mask stays as it is
		la $s0, hpf		# change to hpf 

		
########################################
## the most interesting part - filtering

####   local variables
# t0 - loop counter
# t1 - current byte to change (mask center)
# t2 - current byte to multiplicate with wage and add to sum
# t3 - current wage
# t4 - sum
# t5 - blocks filtered
# t6 - bytes in a block filtered
# t7 - one block size (in bytes)
# t8 - number of blocks
# t9 - first byte of the mask, to tell lpf from hpf when dividing sum

filter_it:
		
		# initialization
		mul $s3, $s3, 3		# width is now in bytes
		sll $t7, $s3, 3 	# block size in bytes
		
		srl $t8, $s4, 3		# blocks quantity
		addiu $t8, $t8, 1	# one more, in case height % blocks quantity != 0
		lb $t9, ($s0)		# first byte of the mask
		
read_buffer:
		# read part of the pixel array
		li $v0, 14
		move $a0, $s1
		la $a1, in_buffer
		move $a2, $t7
		syscall
		
		move $t0, $zero 	# loop counter = 0
		la $t1, in_buffer 	# current pxl = buffer start
		la $s6, out_buffer	# 
		move $t6, $zero		# bytes in one block filtered = 0  
		# now rewrite the first row		
one_row_loop:
		lbu $t2, ($t1)		
		sb $t2, ($s6)
		addiu $t1, $t1, 1
		addiu $s6, $s6, 1
		addiu $t0, $t0, 1
		
		blt $t0, $s3, one_row_loop
		
		addu $t6, $t6, $s3	# bytes in block passed += one row
		
		beq $t6, $t7, whole_block_filtered 
	
		move $t0, $zero
		
		subu $t7, $t7, $s3	# we change it before jumping here
row_first_pxl_loop:			#
		addu $t7, $t7, $s3 	# so we have to restore the proper value here 
			 
		lbu $t2, ($t1)
		sb $t2, ($s6)
		addiu $t1, $t1, 1
		addiu $s6, $s6, 1
		addiu $t0, $t0, 1
		
		subu $t7, $t7, $s3
		blt $t0, 3, row_first_pxl_loop
		addu $t7, $t7, $s3
		
		addu $t6, $t6, 3 	# 3 bytes more passed
		move $t0, $zero

		subiu $s3, $s3, 6 	# we change it before jumping here
loop:		
		addiu $s3, $s3, 6	# so we have to restore the proper value here 
		
		## main loop, in which we change bytes
		##
		## sum up the wages and divide		|````|
		##   the mask looks like this: 	|    |
		##					|____|
		
		move $t4, $zero 	# sum = zero
		
		# we're starting with the left-bottom
		# |_ 
		sub $t2, $t1, $s3 	# one row down
		addi $t2, $t2, -3	# and 3 bytes to the left
		lbu $t2, ($t2)		# get the byte
		lb $t3, ($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# __
		sub $t2, $t1, $s3 	# one row down
		lbu $t2, ($t2)		# get the byte
		lb $t3, 1($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# _|
		sub $t2, $t1, $s3	# one row down
		addi $t2, $t2, 3	# and 3 bytes to the right
		lbu $t2, ($t2)		# get the byte
		lb $t3, 2($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# |-
		addi $t2, $t1, -3	# 3 bytes to the left
		lbu $t2, ($t2)		# get the byte
		lb $t3, 3($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# --
		lbu $t2, ($t1)		# get the byte
		lb $t3, 4($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum
		
		# -|
		addi $t2, $t1, 3	# 3 bytes to the right
		lbu $t2, ($t2)		# get the byte
		lb $t3, 5($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# |` 
		add $t2, $t1, $s3	# one row up
		addi $t2, $t2, -3	# and 3 bytes to the left
		lbu $t2, ($t2)		# get the byte
		lb $t3, 6($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# ``
		add $t2, $t1, $s3	# one row up
		lbu $t2, ($t2)		# get the byte
		lb $t3, 7($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# `|
		add $t2, $t1, $s3	# one row up
		addi $t2, $t2, 3	# and 3 bytes to the right
		lbu $t2, ($t2)		# get the byte
		lb $t3, 8($s0)		# get the wage
		mul $t2, $t2, $t3	# byte*wage
		add $t4, $t4, $t2	# add it to the sum

		# divide the sum
		#   - by 9 if lpf
		#   - by 1 if hpf (do nothing)
		bne $t9, 1, division_done
		div $t4, $t4, 9
		
division_done:
		# the byte value must be in 0-255
		ble $t4, 255, not_too_big
		li $t4, 255
not_too_big:	bge $t4, 0, not_too_small
		li $t4, 0
not_too_small:
		sb $t4, ($s6)		# store byte in the output buffer
		addiu $s6, $s6, 1	# increment the output byte
		addiu $t1, $t1, 1	# 	and the input byte
		addiu $t0, $t0, 1	# 	and the counter
		addiu $t6, $t6, 1	#	and bytes in a block passed
		
		subiu $s3, $s3, 6	# width without pxls on edge
		blt $t0, $s3, loop
		addiu $s3, $s3, 6
		
		move $t0, $zero
		
row_last_pxl_loop:
		lbu $t2, ($t1)
		sb $t2, ($s6)
		addiu $t1, $t1, 1
		addiu $s6, $s6, 1
		addiu $t0, $t0, 1
		
		blt $t0, 3, row_last_pxl_loop

		addiu $t6, $t6, 3	# 3 more bytes passed
		move $t0, $zero
		
		subu $t7, $t7, $s3
		blt $t6, $t7, row_first_pxl_loop # next row to filter
		addu $t7, $t7, $s3
		
		j one_row_loop		# this is the last row - rewrite it
		
		
whole_block_filtered: 		
		addiu $t5, $t5, 1	# incremenet filtered blocks counter
		
		li $v0, 1		# print filtered blocks counter
		move $a0, $t5
		syscall
						
		li $v0, 15		# write the buffer into the output file
		move $a0, $s5
		la $a1, out_buffer
		move $a2, $t7
		syscall			
			
		beq $t5, $t8, whole_filtered
		b read_buffer		# go back to read the next buffer

		## we have filtered the whole image
whole_filtered:				

		# close the files
		li $v0, 16
		move $a0, $s1
		syscall
		
		li $v0, 16
		move $a0, $s5
		syscall
		
		# print the message that we're done
		li $v0, 4
		la $a0, msg_done
		syscall
		
		j exit
		
		# if a file was not found
input_file_err:
		li $v0, 4
		la $a0, msg_inputfile_err
		syscall
		j exit
output_file_err:
		li $v0, 4
		la $a0, msg_outputfile_err
		syscall
	
exit:		# quit
		li $v0, 10
		syscall
