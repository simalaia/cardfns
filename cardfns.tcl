#! /usr/bin/env tclsh

package require cmdline
package require inifile

set def(dot) $env(dots)/cardfns
set def(ed)  "vim"
set def(stk) $def(dot)/var/decks
set 

# Takes a number and converts it to base 60
proc argam {n} {
	return [lindex {0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J \
	                K L M N O P Q R S T U V W X Y Z a b c d \
	                e f g h i j k l m n o p q r s t u v w x} $n]
}

# Returns the current year in base 60
proc Y60 {} {
	set k [gets [open "| echo obase=60; [clock format [clock seconds] -format %Y] | bc"]]
	return "[argam [lindex $k 0]][argam [lindex $k 1]]"
}

# Returns the current month in base 60
proc M60 {} { return [argam [scan [clock format [clock seconds] -format %m] %d]] }

# Returns the current day in base 60
proc D60 {} { return [argam [scan [clock format [clock seconds] -format %e] %d]] }

# Returns the current hour in base 60
proc h60 {} { return [argam [scan [clock format [clock seconds] -format %k] %d]] }

# Returns the current minute in base 60
proc m60 {} { return [argam [scan [clock format [clock seconds] -format %M] %d]] }

# Returns the current second in base 60
proc s60 {} { return [argam [scan [clock format [clock seconds] -format %S] %d]] }

# Creates a card id based on a base 60 encoding of the current time
proc mkcardid {} { return "[Y60][M60][D60][h60][m60][s60]" }

# Truncates a number to two decimal places
proc trunc {i} { return [expr (floor (100.0 * $i))/100] }

# Display message and request response, defaults to no.  Works both graphically and on the commandline
proc nory {m q} {
	global opts
	if {$opts(gui)} {
		return [expr {"no" eq [tk_messageBox -type yesno -message $m -detail $q]}]
	} else {
		puts "$m\n$q \[Y|n\]: "
		return [expr {"n" eq [gets stdin]}]
	}
}

# Display a message either graphically or in text
proc dsp {m} {
	global opts
	if {$opts(gui)} { tk_messageBox -message $m }\
	else { puts $m }
}

# Gets a response either graphically or in text
proc getstr {m} {
	global opts
	set s ""
	if {$opts(gui)} { ::getstring::tk_getString .gs s $m }\
	else { puts $m; set s [gets stdin] }
	return $s
}


proc fuck {} { dsp "valid commands: utime review score today add-card add-deck decks"; exit }

# Return a shuffled list
proc shuf {l} {
	set len [llength $l]
	while {$len} {
		set n [expr {int($len*rand())}]
		set tmp [lindex $l $n]
		lset l $n [lindex $l [incr len -1]]
		lset l $len $tmp
	}
	return $l
}

# Read in a list of lines
proc gulp {fd} {
	set l {}; set fd [open $fd r]
	while {[gets $fd line] >= 0} { lappend l $line }
	close $fd
	return $l
}

# Write out a list of lines
proc splat {op fd c} {
	switch $op w { set fd [open $fd w] } a { set fd [open $fd a] }
	foreach l $c { puts $fd $l }
	close $fd
}

# Filter list
proc filter {f l} {
	set k {}
	foreach e $l { if [$f $e] { lappend k $e } }
	return $k
}

# Add a card to a named deck
proc add-card  {d} {
	if {![deck? $d]} { dsp "Deck does not exist, please add it first"; return }
	set q [getstr "Question: "]
	set a [getstr "Answer: "]
	set c $d/[mkcardid];
	dsp "Cardid: $c\nQuestion: $q\nAnsewr: $a"
	splat w $c [list 0 0 $q $a] }

proc add-deck  {d} { if {![deck? $d]} { file mkdir $d; splat w $d/stat "" } }
proc edit-card {c} { global opts; exec $opts(editor) $c }

# Predicates
proc deck?  {f} { return [file isdirectory $f] }
proc card?  {f} { return [expr {[file isfile $f] && ![regexp "stat" $f]}] }
proc today? {f} { return	[expr {[lindex [gulp $f] 1] == 0 }] }

# Grab lists of cards or decks
proc get-decks { } { return [filter deck? [glob -nocomplain *]] }
proc get-cards { } { return [filter card? [glob -nocomplain */*]] }
proc today     {l} { return [filter today? $l] }

# proc get-stat  {d} { return [gulp $d/stat] }
# proc get-ans   {d} { return [gulp $d/stat] }
# proc done {} {
# 	foreach d [get-decks] {
# 		foreach c [get-stat $d] {
# 			set k($d/$c) }}
# 	return k }


# Update card times
proc utimes {c} {
	if {[lindex $c 1] > 0} {set c [lreplace $c 1 1 [expr [lindex $c 1] - 1]]}
	return $c
}

# Update card schedules
proc usched {c k} {
	set seq {0 5 7 13 23 37 53 89 149 233 379 613 997 1597 2579 4177 6763 10949}
	set k [expr [lindex $c 0] + $k]
	if {$k < 1} {set k 1}
	return [list $k [lindex $seq $k] [lindex $c 2] [lindex $c 3]]
}

# Review today's cards
proc review {all} {
	foreach n $all {
		set d [file dirname $n]; set c [file tail $n]
		splat a $d/stat $c
		if [nory "Card: $d $c\n[lindex [gulp $n] 2]" Continue?] {break}
	}
}

# Score reviewed cards
proc score {d} {
	set k 0; set p [gulp $d/stat]
	if {[llength $p] == 0} { return } else { splat w $d/stat "" }
	foreach f [shuf $p] {
		set c [gulp $d/$f]
		if [nory "Card: $d $f\n[lindex $c 2]\n[lindex $c 3]" Correct?] {
			splat w $d/$f [usched $c -1]
		} else {
			set k [expr $k + 1]
			splat w $d/$f [usched $c 1]
		}
	}

	set num [llength $p]
	dsp "Total:      $num
Correct:    $k
Incorrect:  [expr $num - $k]
Percentage: [trunc [expr double($k) / $num]]"
}

# Functions defining the UI
proc ui-utime {} { foreach c [get-cards] { splat w $c [utimes [gulp $c]] } }
proc ui-review {} { review [shuf [today [get-cards]]] }
proc ui-score {} { foreach d [get-decks] { score $d } }
proc ui-today {} { set k [today [get-cards]]; if [llength $k] {dsp $k} else {dsp "None"} }
proc ui-add {f} {
	global opts
	if {$opts(deck) eq ""} {dsp "Need a deck name: -deck <name>"; exit}
	$f $opts(deck) }
proc ui-decks { } { foreach d [get-decks] { dsp $d } }

# Define the text UI
proc tui {} {
	global opts

	switch $opts(argv) {
		utime    { ui-utime        } review   { ui-review       }
		score    { ui-score        } today    { ui-today        }
		add-card { ui-add add-card } add-deck { ui-add add-deck }
		decks    { ui-decks        } default  { fuck; exit      }} }

# Define the graphical UI
proc gui {} {
	global opts

	package require Tk
	package require getstring
	
	image create photo leaf -file $cnf(leaf)
	
	wm title . "Card functions"
	grid [ttk::frame .c] -column 0 -row 0 -sticky nwes

	grid [ttk::label .c.logo -image leaf] -column 1 -row 1 -columnspan 4
	# ttk::label .label -text Stack
	grid [ttk::entry .c.s -textvariable opts(stack)] -column 1 -row 2 -columnspan 2 -padx 2 -pady 2
	.c.s state disabled
	bind .c.s <1>      {set opts(stack) [tk_chooseDirectory]; cd $opts(stack)}
	grid [ttk::button .c.u -command gui-utime  -text "update time"] -column 3 -row 2 -padx 2 -pady 2
	grid [ttk::button .c.t -command gui-today  -text today]         -column 4 -row 2 -padx 2 -pady 2
	grid [ttk::button .c.r -command gui-review -text review]        -column 3 -row 3 -padx 2 -pady 2
	grid [ttk::button .c.o -command gui-score  -text score]         -column 4 -row 3 -padx 2 -pady 2
	grid [ttk::button .c.c -command gui-card   -text "add card"]    -column 1 -row 3 -padx 2 -pady 2
	grid [ttk::button .c.d -command gui-deck   -text "add deck"]    -column 2 -row 3 -padx 2 -pady 2

	proc nop {} { dsp "This is a nop" }
	proc gui-card {} {
		if {[::getstring::tk_getString .gs opt(deck) "Which deck to add to?:"]} {
			ui-add add-card } }
	proc gui-deck {} {
		if {[::getstring::tk_getString .gs opt(deck) "Name of new deck?:"]} {
			ui-add add-deck } }
	proc gui-utime {} { ui-utime; dsp "Done" }
	proc gui-today {} { ui-today }
	proc gui-review {} { ui-review }
	proc gui-score {} { ui-score }
}


# Read or create the config file
if {[file isfile $def(dot)/etc/config]} {
	set cfile [::ini::open $def(dot)/etc/config]
	set x [::ini::get $cfile config]
	dict for {k v} $x { set cnf($k) $v }

	set params [list \
		[list conf.arg   $cnf(conf)    "Where to find the config directory" ] \
		[list editor.arg $cnf(editor)  "Which editor to invoke" ] \
		[list stack.arg  $cnf(stack)   "Where to find the decks" ] \
		[list deck.arg   ""            "Name for the new deck" ] \
		[list gui                      "Run the gui" ] ]

} else {
	splat w $def(dot)/etc/config "\[config\]"
	set cfile [::ini::open $def(dot)/etc/config]

	set params [list \
		[list conf.arg   $def(dot)   "Where to find the config directory" ] \
		[list editor.arg $def(ed)    "Which editor to invoke" ] \
		[list stack.arg  $def(stk)   "Where to find the decks" ] \
		[list deck.arg   ""          "Name for the new deck" ] \
		[list gui                    "Run the gui" ] ]
}

# Do some stuff, not sure what stuff anymore (and I'm too lazy to work it out), but I'm sure it made sense at the time
set usage "- card functions, what else could I possibly say...\ncall as me \[opts\] command"
array set opts [cmdline::getoptions argv $params $usage]

dict for {k v} [array get opts] {
	if {!($k eq "gui") && !($k eq "deck")} { ::ini::set $cfile config $k $v }
}
::ini::commit $cfile
::ini::close $cfile
set opts(argv) $argv
set opts(argc) $argc

cd $opts(stack)
if {!$opts(gui)} { if {[llength $opts(argv)] != 1} { fuck }; tui } else { gui }



