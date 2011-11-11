#!/usr/bin/perl
# Bananabot 1.0a @2004 Thomas Castiglione #
# Anyone is permitted to use and modify	#
# this program, as long as they preserve  #
# this notice and note their changes.	 #
# castiglione@mac.com

# includes

use warnings; use strict;

use POE;
use POE::Component::IRC;
use Socket;
use POSIX;
use Math::Random::MT qw(srand rand);
use POSIX qw(ceil floor);
use Storable

# constants
my $version		= '1.10';
my $channel		= '#pc-ooc';
my $nick		= "bananabot";
my $username		= "bananabot";# . $version ;
my $password		= 'bananabot';
my $server		= 'irc.sorcery.net';
my $port		= '6667';
my $owner 		= 'banana';
my $network		= '$network';
my $totalcolour		= '04';
my $rollcolour		= '12';
my $dicecolour		= '03';
my $successcolour	= '13';
my $LOG			= 0;
my $DEBUG		= 0;
my $interval		= 0;

# initial aliases
my %aliases = (
	'fudge',		'4dF',
	'gurps',		'3d6',
	'(fs|feng(shui)?)',	'o-o',
	'(rand)?char',		'4d6li,6',
	'(\d*)\s*w\s*(\d*)',	'$1\@$2#d10',
	'(\d*)\s*g\s*(\d*)',	'$1\@$2#3d6',
	'(\d*)\s*sr\s*(\d*)',	'$1\@\@$2#d6',
	'(\d*)k(\d*)',		'$1o10l@{[$1-$2]}i',
	'(\d*)e',		'$1d6l@{[$1-3]}',
	'dagon',		'3#4d5l+3,3',
	'duel',			'd10000'
);
#				'vs(\D*)(\d*)(\D*)(\d*)' '\"$1: \"d20+$2&\"$3: \"d20+$4');
# initialise last-seen db
my %last = ();
my %lastwhen = ();
# or read in from log if it exists
my $lastfile = $nick.'.last';
if (-e $lastfile && -r $lastfile){
	my $rlast = retrieve($nick.'.last'); 
	%last = %$rlast;
}
my $whenfile = $nick.'.when';
if (-e $whenfile && -r $whenfile) {
	my $rwhen = retrieve($nick.'.when');
	%lastwhen = %$rwhen;
}

# initialise POE
POE::Component::IRC->spawn(alias => $network);				#the IRC network
POE::Session->create(
	inline_states => {
		_start		=> \&on_start,				# pre-init function
		irc_001		=> \&on_connect,			# post-init function
		irc_public	=> \&on_public,				# listen for public messages
		irc_msg		=> \&on_private,			# listen for private messages
		irc_disconnected => \&on_disconnect,			# listen for disconnections
		irc_kick	=> \&on_kick				# listen for kicks
	}
);
my $exit = 0;
# initialise RNG
srand(time());
# start the event loop
$poe_kernel->run();							# run forever

# go into a loop of attempting to connect
# currently only tries once
my ($who, $what, $when, $where, $why, $lines); #TODO: sort this mess out

sub on_start {							
	my $address = inet_ntoa(inet_aton($server));		# translate address to IP
	
	if ($LOG == 1) {print "on_start\n";}
	
	$poe_kernel->post($network, 'register', 'all');		# create component
	$poe_kernel->post($network, connect => {		# connect to IRC server
		Nick	=> $nick,
		Username=> $username,
		Ircname	=> "!help for help",	# can't have username as second word of gcos, or get mistaken for Fizzer and z-lined 
		Server	=> $address,
		Port	=> $port,
		Flood	=> 1			# allow more than 5 lines unthrottled >:(
	});
}

# we've connected to the server, now join the channel
sub on_connect {
	daemon();	# Once timers are working, move this to just before run()
	if ($LOG == 1) {print "/join $channel\n";}
	$poe_kernel->post($network, join => $channel);
	$poe_kernel->post($network, privmsg => 'NickServ', "identify $password") unless ($password eq '');
}

# daemonize - reproduce asexually, eat young
sub daemon {
	my $pid = fork();
	exit if $pid;
	die "Can't fork: $!" unless defined($pid);
	POSIX::setsid() or die "Can't start session: $!";	#Is the namespace actually necessary here?
}

# autorejoin - necessary out there in the wild internet where people kick bots for fun
# something to look into: are there other ways of being removed from a channel?
sub on_kick {
	my $knick = $_[ARG2];
	if ($knick eq $nick) {
		$poe_kernel->post($network, join => $channel);
	}
}

sub on_private  {	#Received a private message
	my ($user, $channel, $_) = @_[ARG0, ARG1, ARG2];
	$user = (split /!/, $user)[0];
	
	if ($LOG == 1) {	#be an actual IRC client
		my $ts = scalar(localtime);
		print "[$ts] *$user* $_\n";
	}
	
	my $cmd;
	my $msg;
	if (/^\!/) {	#nasty nasty regexes
		if (/^\![a-zA-Z]+\ .+/) {
			s/^\!([a-zA-Z]+)\ (.*)/$1SPLITTERHACK$2/;
			($cmd, $msg) = split(/SPLITTERHACK/);
		} else {
			s/^\!//;
			my $cmd = $_;
			$msg = '';
		}
		do_command($user, $user, $cmd, $msg);
	} else {
		$_ = '!' . $_;
		if (/^\![a-zA-Z]+\ .+/) {
			s/^\!([a-zA-Z]+)\ (.*)/$1SPLITTERHACK$2/;
			($cmd, $msg) = split(/SPLITTERHACK/);
		} else {
			s/^\!//;
			$cmd = $_;
			$msg = '';
		}
		do_command($user, $user, $cmd, $msg);
	}
}

sub on_public {
	my ($user, $channel, $_) = @_[ARG0, ARG1, ARG2];
	$user = (split /!/, $user)[0];
	$channel = $channel->[0];
	
	#### LIGHTS HACK ####
	if ($_ =~ /banana-chan/) {
		$poe_kernel->post($network, 'kick'=>$channel, $user, "HA! HA! I'm using THE INTERNET!");
	}
	## END LIGHTS HACK ##
	
	if ($LOG == 1) {
		my $ts = scalar(localtime);
		print "[$ts] <$user> $_\n";
	}
	
	$last{$user} = $_;	# add to last database
	$lastwhen{$user} = time();

	my $cmd;
	my $msg;
	if (/^\!/) {	#the same nasty regexes all over again
		if (/^\![a-zA-Z]+\ .+/) {
			s/^\!([a-zA-Z]+)\ (.*)/$1SPLITTERHACK$2/;
			($cmd, $msg) = split(/SPLITTERHACK/);
		} else {
			s/^\!//;
			$cmd = $_;
			$msg = '';
		}
		do_command($user, $channel, $cmd, $msg);
	}
}

sub on_disconnect {	
	if ($exit == 1) {	# assume the disconnect was intentional and exit
		exit(0);
	} else {
		on_start();	# restart the timers
	}
}

sub do_command {			# post-parsing command switcher
	($who, $where, $what, $why) = @_;
	if ($who =~ /dong/i) {		# hack for Roseo's stupid thing
		return;
	}
	my $aliaslist = join('|', (keys %aliases));
	if		($what =~ /^help/i) {
		cmd_help($why);
	} elsif	($what =~ /^quit/i) {
		cmd_quit();
	} elsif	($what =~ /^mquit/i) {
		cmd_mquit();
	} elsif	($what =~ /^r(oll)?/i) {
		cmd_roll();
	} elsif ($what =~ /^join/i) {
		cmd_join();
	} elsif ($what =~ /^alias/i) {
		cmd_alias();
	} elsif	($what =~ /^(seen|last(seen)?)/i) {
		cmd_lastseen();
	} elsif ($what =~ /^botsnack/i) {
		cmd_botsnack();
#	} elsif ($what =~ /^($aliaslist)/i) {
#		$why = $what . ' ' . $why;
#		cmd_roll();
	} elsif ($what !~ /^[\s!]*$/) {
		$why = $what;
		cmd_roll();
	}
}

sub cmd_lastseen {
	if ($why =~ /$who/i) {
		#$poe_kernel->post($network, 'kick'=>$where, $who, "HA! HA! I'm using THE INTERNET!");
	} else {
		foreach $nick (keys %last) {
			my $safenick = $nick;
			$safenick =~ s/\|/\\\|/g;
			if ($why =~ /^$safenick$/i) {
				$why = $nick;
				$when = $lastwhen{$why};
				$when = time() - $when;
				$what = $last{$why};
				
				if ($when > 60) {
					my $whenm = floor($when / 60);
					my $whens = $when - $whenm * 60;
					if ($whenm > 60) {
						my $whenh = floor($whenm / 60);
						$whenm = floor($whenm - $whenh * 60);
						$poe_kernel->post($network, 'privmsg'=>$where, "I saw $nick $whenh hour" . ($whenh > 1 ? "s" : "") . " and $whenm minutes ago, saying \"\002$what\002\".");
					} else {
						$poe_kernel->post($network, 'privmsg'=>$where, "I saw $nick $whenm minute" . ($whenm > 1 ? "s" : "") . " and $whens seconds ago, saying \"\002$what\002\".");
					}
				} else {
					$poe_kernel->post($network, 'privmsg'=>$where, "I saw $nick $when seconds ago, saying \"\002$what\002\".");
				}
				return;
			}
		}
		$poe_kernel->post($network, 'privmsg'=>$where, "I haven't seen ${why}.");
	}
}

sub cmd_alias {
	if ($why eq '') {
		$poe_kernel->post($network, 'privmsg'=>$where, "\003${rollcolour}Currently defined aliases:");
		foreach my $alias (keys %aliases) {
			$poe_kernel->post($network, 'privmsg'=>$where, "\003$dicecolour$alias\t\003$totalcolour$aliases{$alias}");
		}
	} else {
		my ($alias, @definition) = split(/\s/, $why);
		my $definition = "@definition";
		if ($alias eq '') {
			error(9, "The correct usage is !alias <alias> definition, blank definition clears");
		} elsif ($alias =~ /(\d|(\d*)\s*g\s*(\d*)|(\d*)\s*w\s*(\d*)|fudge|^.$)/ && ($who ne $owner)) {
			error(2, "Only $owner can set certain 'dangerous' aliases.");
		} else {
			if ($definition ne '') {
				$aliases{$alias} = $definition;
			} else {
				delete $aliases{$alias};
			}
		}
	}	
}

# For #partyhard botmolesters
sub cmd_botsnack {
	error(0, 'Who do you think I am, foxxbot?');
}

# Quits
sub cmd_quit {
	if ($who eq $owner) {
		$exit = 1;
		store(\%last, $lastfile);
		store(\%lastwhen, $whenfile);
		$poe_kernel->post($network, 'quit', $why);
	} else {
		error(45, "Only $owner can order me to quit.");
	}	
}

# WHAT IS THIS I DON'T REMEMBER
sub cmd_mquit {
	if ($who eq $owner) {
		$poe_kernel->post($network, 'quit', $why);
	} else {
		error(49, "Only $owner can order me to quit.");
	}	
}

# This should be improved to allow anyone to use it if the bot's not in a channel
sub cmd_join {
	if ($who eq $owner) {
		$poe_kernel->post($network, 'part', $channel);
		$channel = $why;
		$poe_kernel->post($network, 'join', $channel);
	} else {
		error(46, "Only $owner can order me to join channels.");
	}	
}

# This could do with some actual documentation
sub cmd_help {
	$_ = shift;
	if ($_ eq '') {$_ = 'general';}
	if (/general/i) {
		$poe_kernel->post($network, privmsg => $where, 'usage:');
		$poe_kernel->post($network, privmsg => $where, '  !command <arguments>');
		$poe_kernel->post($network, privmsg => $where, '  /msg bananabot !command <arguments>');
		$poe_kernel->post($network, privmsg => $where, 'commands: alias, help, join, quit, roll, seen');
		$poe_kernel->post($network, privmsg => $where, 'commands: alias, help, join, quit, roll, seen');
	} elsif (/alias/i) {
		$poe_kernel->post($network, privmsg => $where, 'Aliases are regular expressions used to add features to the dice language.');
		$poe_kernel->post($network, privmsg => $where, 'To set an alias:');
		$poe_kernel->post($network, privmsg => $where, '  !alias <alias> <definition>');
		$poe_kernel->post($network, privmsg => $where, 'To remove an alias:');
		$poe_kernel->post($network, privmsg => $where, '  !alias <alias>');
		$poe_kernel->post($network, privmsg => $where, 'To view current aliases:');
		$poe_kernel->post($network, privmsg => $where, '  !alias');
	} else {
		error(-1, "No help available for topic.");
	}
}

sub cmd_roll {
	my ($die, $n, $s, $o, $j, $q, $type, @dice, $notones, $answercolour);
	my $expression = $why;
	### INTERPRET MACROS ###
#	$expression =~ s/(\d*)\s*w\s*(\d*)/$1\@$2#d10/ig;	# hack to make args work
	foreach my $alias (keys %aliases) {
#		$poe_kernel->post($network, privmsg => $where, "looking for $alias");
		eval('$expression =~ s/$alias/' . $aliases{$alias} . '/ig;');
	}
	$poe_kernel->post($network, privmsg => $where, "DEBUG: \$expression = $expression") unless $DEBUG == 0;
	### CALCULATE NUMBER OF ROLLS #############################
	$lines = 1;
	my $target = 0;
	my $ones = -1;
	my $fre = '\s*((\d*)\s*(@@?\s*\d*)?)\s*';
	if ($expression =~ /^${fre}#/) {
		$expression =~ s/${fre}#([^,]+)/and_repeat($4, $1)/e;
	} elsif ($expression =~ /#$fre$/) {
		$expression =~ s/([^,]+)#$fre/and_repeat($1, $2)/e;
	}
	if ($expression =~ /,\s*\d+/) {
		($expression, $lines) = split(/\s*,\s*/, $expression);
	} elsif ($expression =~ /\d+\s*,/) {
		($lines, $expression) = split(/\s*,\s*/, $expression);
	}
	if ($lines > 10) {
		$lines = 10;
	}
	### SEPERATE BATCH ROLLS #################################
	for (my $i = 0; $i < $lines; $i++) {
		if ($ones > -1) {
			$ones = 0;	# shadowrun check-for-ones
			$notones = 0;
		}
		my @batch = split('&', $expression);
		my $line = '';
		my $successes = 0;
		my $swmishap = 0;
		foreach $_ (@batch) {
	### IMPLEMENT ** OPERATOR #################################
			while (/\*\*/) {				
				s/([^,#]+)\*\*\s*(\d*)/roll_repeat($1, $2)/e;
			}
			my $p = $_;						#for pretty-printing
			s/".*"//g;
			$p =~ s/"(.*)"/$1/g;
	### SUBSTITUTE DIE ROLL RESULTS FOR THE d-EXPRESSIONS ####		7dfh5l
			my @rolls = ($_ =~ /(\d*[do]\d*f?[hl]?\d*[hl]?\d*i?|\d*s)/ig);
			for my $roll (@rolls) {
				my $result = 0;
				my $presult = "\003$dicecolour";
				my $orig = $roll;
	### CHECK FOR STAR WARS FAGGOTRY ###
				if ($roll =~ /s/i) {
					my ($die);
					# OK, this is a star wars roll - TIME TO GO INSANE >:(
					($n) = ($roll =~ /\d+/g);
					$poe_kernel->post($network, privmsg => $where, "found star wars roll: $n") unless !$DEBUG;
					if ($n == '') {$n = 1;}
					$s = 6;
					# Roll non-wild dice
					my $highest = 0;
					for (my $j = 0; $j < ($n - 1); $j++) {
						$die = int(rand($s)) + 1;
						$result += $die;
						$presult .= '+' unless ($j == 0);
						$presult .= "$die";
						if ($die > $highest) { $highest = $die; }
					}
					# Wild die WTF
					$presult .= '|';
					$die = int(rand($s)) + 1;
					if ($die == 1) {
						$swmishap = 1;
						$result -= $highest;
						$presult .= '-' . $highest;
					} else {
						$result += $die;
						$presult .= $die;
						while ($die == 6) {
							$die = int(rand($s)) + 1;
							$result += $die;
							$presult .= '+' . $die;
						}
					}
				} else {
	### CONFORM TO ROLL FORMAT: a(d|o)blchd, {a,c,d} numbers {b} number or f
				if ($roll !~ /l/i) {
					$roll .= 'l0';
				}
				if ($roll !~ /h/i) {
					$roll .= 'h0';
				}
				$roll =~ s/l([^0123456789])/l1$1/i;
				$roll =~ s/h([^0123456789])/h1$1/i;
				$roll =~ s/h(\d*)l(\d*)/l$2h$1/i;	
				if ($roll =~ /^(d|o)/i) {
					$roll = '1' . $roll;
				}
				$roll =~ s/(d|o)(h|l|i)/${1}6$2/i;
	### PARSE #################################################
				my $individual;
				if ($roll =~ /i/i) {
					$individual = 1;
					$roll =~ s/i//i;
				} else {
					$individual = 0;
				}
				($roll, my $h) = split(/h/i, $roll);
				($roll, my $l) = split(/l/i, $roll);
				if ($roll =~ /d/i) {
					($n, $s) = split(/d/i, $roll);
					$type = 'd';
					$o = 0;
				} elsif ($roll =~ /o/) {
					($n, $s) = split(/o/i, $roll);
					$type = 'o';
					$o = 1;
				} elsif ($roll =~ /s/) {
					($n, $s) = split(/s/i, $roll);
					$type = 's';
				}
				if ($n < 1) {
 					error(100, "I can't roll less than 1 dice.");
 					return;
 				}
 				if ($n > 39278) {
 					error(39278, "I can't roll that many dice.");
 					return;
 				}
 				if ($s > 24789653974) {
 					error(24789653974, "I'M A PROFESSIONAL JOURNALIST. I THINK I KNOW HOW TO OPERATE A FUCKING HAT!");
 					return;
 				}
 				if ($s !~ /f/i && $s < 2) {
 					error(200, "$s is an invalid number of sides.");
 					return;
 				}
				$poe_kernel->post($network, privmsg => $where, "about to roll; \$n=$n \$s=$s \$i=$i \$h=$h \$l=$l") unless !$DEBUG;
	### ROLL ROLL ROLL ROLL ROLL ROLL ROLL ### BANANABOT ######			
				@dice = ();
				my (@sorteddice, @dropped, $top);
				if ($o == 0 && $s !~ /f/i) {
					for ($j = 0; $j < $n; $j++) {
 						$die = int(rand($s)) + 1;
 						if ($ones > -1) {
 							if ($die == 1) {
 								$ones++;
 							} else {
 								$notones++;
 							}
 						}
						push(@dice, $die);
					}
				} elsif ($o == 0 && $s =~ /f/i) {
					for ($j = 0; $j < $n; $j++) {
 						$die = int(rand(3)) - 1;
						push(@dice, $die);
					}
				} elsif ($o == 1 && $s !~ /f/i) {
					for ($j = 0; $j < $n; $j++) {
 						$die = int(rand($s)) + 1;
 						if ($ones > -1) {
 							if ($die == 1) {
 								$ones++;
 							} else {
 								$notones++;
 							}
 						}
 						push(@dice, $die);
 						if ($die == $s) {
 							$j--;
 						}
					}
				} elsif ($o == 1 && $s =~ /f/i) {
					for ($j = 0; $j < $n; $j++) {
 						$die = int(rand(3)) - 1;
						push(@dice, $die);
 						if ($die == 1) {
 							$j--;
 						}
					}
				}
				if ($h + $l > $n) {
 					error(88, "You can't drop more dice than are rolled.");
 					return;
 				}
				foreach $die (@dice) {
					if ($s =~ /f/i) {			
						if ($die == 1) {$presult .= '+';}
 						if ($die == 0) {$presult .= ' ';}
 						if ($die == -1) {$presult .= '-';}
 					} 
 					$result += $die;
 				}
 				if ($s !~ /f/i) {
 					if ($individual == 0) {
 						$presult .= pad($n, $s, $result);
 					} else {
 						foreach $die (@dice) {
 							$presult .= pad(1, $s, $die) . '+';
 						}
 						chop($presult);
 					}
 				}
 				@sorteddice = sort { $a <=> $b } @dice;
 				if ($l > 0 && $s !~ /f/i) {
		 			@dropped = @sorteddice[$0 .. ($l-1)];
		 			
		 			foreach $die (@dropped) {
		 				$result -= $die;
		 				$presult .= '-' . pad(1, $s, $die);
		 			}
	 			}
	 			if ($h > 0 && $s !~ /f/i) {
	 				$top = $#sorteddice + 1;
		 			@dropped = @sorteddice[($top-$h) .. ($top-1)];
		 			
		 			foreach $die (@dropped) {
		 				$result -= $die;
		 				$presult .= '-' . pad(1, $s, $die);
		 			}
	 			}
	 			}
				$presult .= "\003$rollcolour";
				#replace the $roll with the new total for that $roll
				s/$orig/($result)/;
				$p =~ s/$orig/$presult/;
			}
	### MAKE SURE ONLY VALID SYNTAX REMAINS ###################
			s/x/\*/gi;	#convenience, allow x for *
			s/\^/\*\*/g;	#convenience, allow ^ for **
			s/p/\+/gi;	#convenience, allow p for +
			unless(m/^[\d\s\(\)\+\-\*\/\%\.]+$/) {
				error(-8, "I don't understand \"\002$why\002\".");
				return;
			}
	### EVALUATE THE ANSWER ###################################
			my $answer = eval;
#			unless ($answer =~ /^[-\d\.]+$/) { #This should never be reached
#				error(42, "'$_' evaluates to unacceptable result '$answer'");
#				return;
#			}
#			$p =~ s/^\s*(.+)\s*$/$1/;
			$q = $p;
			$q =~ s/\".*\"//g;
			if ($answer < $target || $target == 0) {
				$answercolour = $totalcolour;
			} else {
				$successes++;
				$answercolour = $successcolour;
			}
			if($q =~ /[^\s\d\003]/) {
				$answer = "\003${rollcolour}$p = \003${answercolour}$answer";
			} else {
				$answer = "\003${answercolour}$answer";
			}
			$line .= $answer . " ";
		}
#		if ($successes > 0) {
#			$line .= "($successes success";
#			if ($successes > 1) {
#				$line .= 'es';
#			}
#			$line .= ')';
#		}
		if ($swmishap) {$line .= "(or mishap)";}
		if ($ones > -1) {
			$line .= "\003${rollcolour}($successes hit" . ($successes != 1 ? "s" : "") . ", " . ($notones <= $ones ? "\003${totalcolour}" : "") . "$ones one" . ($ones != 1 ? "s" : "") . "\003${rollcolour})";
		}
		$poe_kernel->post($network, privmsg => $where, "$who, $line");
	}
	
	return;
}

sub roll_repeat {
	my ($expr, $factor) = @_;
	if ($factor > 128 || $factor < 1) {
		error(220, "Someone's playing silly buggers.");
		return "fail";
	}
	my $exprplus = $expr . ' + ';
	return (($exprplus x ($factor - 1)) . $expr);
}

sub and_repeat {
	my ($expr, $factor) = @_;
	if ($factor =~ /@@/) {	#shadowrun roll
		my $ones = 0;
		if ($factor !~ /@@\d/) {
			$factor .= '5';
		}
		$factor =~ s/@@/@/;
	}
	if ($factor eq '') {
		$factor = '1@0';
	} elsif ($factor !~ /@/) {
		$factor .= '@0';
	} elsif ($factor =~ /^@/) {
		$factor = '1' . $factor;
	}
	($factor, my $target) = split(/@/, $factor);
	if ($factor > 128 || $factor < 1) {
		error(220, "Someone's playing silly buggers.");
		return "fail";
	}
	my $exprplus = $expr . '&';
	return (($exprplus x ($factor - 1)) . $expr);
}

sub error() {
	my $n = shift;
	my $r = shift;
	$poe_kernel->post($network, privmsg => $where, "$who,\003$rollcolour Error: $r\003");
}

sub pad() {
	my $nd = shift;
	my $sd = shift;
	my $inp = shift;

	if ($lines == 1) {
		return $inp;
	}
	
	my $maxlen;
	if ($sd =~ /f/i) {
		$maxlen = $nd;
	} else {
		$maxlen = length ($nd * $sd);
	}
	
	for (my $k = length $inp; $k < $maxlen; $k++) {
		$inp .= ' ';
	}
	
	return $inp;
}
