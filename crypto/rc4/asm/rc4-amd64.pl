#!/usr/bin/env perl
#
# ====================================================================
# Written by Andy Polyakov <appro@fy.chalmers.se> for the OpenSSL
# project. Rights for redistribution and usage in source and binary
# forms are granted according to the OpenSSL license.
# ====================================================================
#
# 2.22x RC4 tune-up:-) It should be noted though that my hand [as in
# "hand-coded assembler"] doesn't stand for the whole improvement
# coefficient. It turned out that eliminating RC4_CHAR from config
# line results in ~40% improvement (yes, even for C implementation).
# Presumably it has everything to do with AMD cache architecture and
# RAW or whatever penalties. Once again! The module *requires* config
# line *without* RC4_CHAR! As for coding "secret," I bet on partial
# register arithmetics. For example instead 'inc %r8; and $255,%r8'
# I simply 'inc %r8b'. Even though optimization manual discourages
# to operate on partial registers, it turned out to be the best bet.
# At least for AMD... How IA32E would perform remains to be seen...

$output=shift;

$win64a=1 if ($output =~ /win64a.[s|asm]/);

open STDOUT,">$output" || die "can't open $output: $!";

if (defined($win64a)) {
    $dat="%rcx";	# arg1
    $len="%rdx";	# arg2
    $inp="%rsi";	# r8, arg3 moves here
    $out="%rdi";	# r9, arg4 moves here
} else {
    $dat="%rdi";	# arg1
    $len="%rsi";	# arg2
    $inp="%rdx";	# arg3
    $out="%rcx";	# arg4
}

$XX="%r10";
$TX="%r8";
$YY="%r11";
$TY="%r9";

sub PTR() {
    my $ret=shift;
    if (defined($win64a)) {
	$ret =~ s/\[([\S]+)\+([\S]+)\]/[$2+$1]/g;   # [%rN+%rM*4]->[%rM*4+%rN]
	$ret =~ s/:([^\[]+)\[([^\]]+)\]/:[$2+$1]/g; # :off[ea]->:[ea+off]
    } else {
	$ret =~ s/[\+\*]/,/g;		# [%rN+%rM*4]->[%rN,%rM,4]
	$ret =~ s/\[([^\]]+)\]/($1)/g;	# [%rN]->(%rN)
    }
    $ret;
}

$code=<<___ if (!defined($win64a));
.text

.globl	RC4
.type	RC4,\@function
.align	16
RC4:	or	$len,$len
	jne	.Lentry
	repret
.Lentry:
___
$code=<<___ if (defined($win64a));
TEXT	SEGMENT
PUBLIC	RC4
ALIGN	16
RC4	PROC NEAR
	or	$len,$len
	jne	.Lentry
	repret
.Lentry:
	push	%rdi
	push	%rsi
	sub	\$40,%rsp
	mov	%r8,$inp
	mov	%r9,$out
___
$code.=<<___;
	add	\$8,$dat
	movl	`&PTR("DWORD:-8[$dat]")`,$XX#d
	movl	`&PTR("DWORD:-4[$dat]")`,$YY#d
	test	\$-8,$len
	jz	.Lloop1
.align	16
.Lloop8:
	movq	`&PTR("QWORD:[$inp]")`,%rax

	inc	$XX#b
	movl	`&PTR("DWORD:[$dat+$XX*4]")`,$TX#d
	add	$TX#b,$YY#b
	movl	`&PTR("DWORD:[$dat+$YY*4]")`,$TY#d
	movl	$TX#d,`&PTR("DWORD:[$dat+$YY*4]")`
	movl	$TY#d,`&PTR("DWORD:[$dat+$XX*4]")`
	add	$TY#b,$TX#b
	inc	$XX#b
	movl	`&PTR("DWORD:[$dat+$TX*4]")`,$TY#d
	xor	$TY,%rax
___
for ($i=1;$i<=6;$i++) {
$code.=<<___;
	movl	`&PTR("DWORD:[$dat+$XX*4]")`,$TX#d
	add	$TX#b,$YY#b
	movl	`&PTR("DWORD:[$dat+$YY*4]")`,$TY#d
	movl	$TX#d,`&PTR("DWORD:[$dat+$YY*4]")`
	movl	$TY#d,`&PTR("DWORD:[$dat+$XX*4]")`
	add	$TY#b,$TX#b
	movl	`&PTR("DWORD:[$dat+$TX*4]")`,$TY#d
	shl	\$`8*$i`,$TY
	inc	$XX#b
	xor	$TY,%rax
___
}
$code.=<<___;
	movl	`&PTR("DWORD:[$dat+$XX*4]")`,$TX#d
	add	$TX#b,$YY#b
	movl	`&PTR("DWORD:[$dat+$YY*4]")`,$TY#d
	movl	$TX#d,`&PTR("DWORD:[$dat+$YY*4]")`
	movl	$TY#d,`&PTR("DWORD:[$dat+$XX*4]")`
	sub	\$8,$len
	add	$TY#b,$TX#b
	add	\$8,$out
	movl	`&PTR("DWORD:[$dat+$TX*4]")`,$TY#d
	shl	\$56,$TY
	add	\$8,$inp
	xor	$TY,%rax

	mov	%rax,`&PTR("QWORD:-8[$out]")`

	test	\$-8,$len
	jnz	.Lloop8
	cmp	\$0,$len
	jne	.Lloop1
.Lexit:
	movl	$XX#d,`&PTR("DWORD:-8[$dat]")`
	movl	$YY#d,`&PTR("DWORD:-4[$dat]")`
___
$code.=<<___ if (defined($win64a));
	add	\$40,%rsp
	pop	%rsi
	pop	%rdi
___
$code.=<<___;
	repret
.align	16
.Lloop1:
	movzb	`&PTR("BYTE:[$inp]")`,%eax
	inc	$XX#b
	movl	`&PTR("DWORD:[$dat+$XX*4]")`,$TX#d
	add	$TX#b,$YY#b
	movl	`&PTR("DWORD:[$dat+$YY*4]")`,$TY#d
	movl	$TX#d,`&PTR("DWORD:[$dat+$YY*4]")`
	movl	$TY#d,`&PTR("DWORD:[$dat+$XX*4]")`
	add	$TY#b,$TX#b
	movl	`&PTR("DWORD:[$dat+$TX*4]")`,$TY#d
	xor	$TY,%rax
	inc	$inp
	movb	%al,`&PTR("BYTE:[$out]")`
	inc	$out
	dec	$len
	jnz	.Lloop1
	jmp	.Lexit
___
$code.=<<___ if (defined($win64a));
RC4	ENDP
TEXT	ENDS
END
___
$code.=<<___ if (!defined($win64a));
.size	RC4,.-RC4
___

$code =~ s/#([bwd])/$1/gm;
$code =~ s/\`([^\`]*)\`/eval $1/gem;

if (defined($win64a)) {
    $code =~ s/\.align/ALIGN/gm;
    $code =~ s/[\$%]//gm;
    $code =~ s/\.L/\$L/gm;
    $code =~ s/([\w]+)([\s]+)([\S]+),([\S]+)/$1$2$4,$3/gm;
    $code =~ s/([QD]*WORD|BYTE):/$1 PTR/gm;
    $code =~ s/mov[bwlq]/mov/gm;
    $code =~ s/movzb/movzx/gm;
    $code =~ s/repret/DB\t0F3h,0C3h/gm;
} else {
    $code =~ s/([QD]*WORD|BYTE)://gm;
    $code =~ s/repret/.byte\t0xF3,0xC3/gm;
}
print $code;