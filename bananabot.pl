#!/usr/bin/perl
# Bananabot 1.0a @2004 Thomas Castiglione #
# Anyone is permitted to use and modify	#
# this program, as long as they preserve  #
# this notice and note their changes.	 #
# castiglione@mac.com

# includes

use warnings; use strict;
use 5.010;

use Try::Tiny;
use POE;
use POE::Component::IRC;
use Socket;
use POSIX;
use Math::Random::MT qw(srand rand);
use POSIX qw(ceil floor);
use Storable;

# constants
my $version		= '1.10';
my $channel		= '#bananabot';
my $nick		= "bananabot";
my $username		= "bananabot";# . $version ;
my $password		= 'bananabot';
my $server		= 'irc.ucc.asn.au';
my $port		= '6667';
my $owner		= 'squimmy';
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


#my ($when, $lines); #TODO: sort this mess out

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
	private_message('NickServ', "identify $password") unless ($password eq '');
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
	my ($user, $channel, $text) = @_[ARG0, ARG1, ARG2];
	$user = (split /!/, $user)[0];
	
	if ($LOG == 1) {	#be an actual IRC client
		my $ts = scalar(localtime);
		print "[$ts] *$user* $text\n";
	}
	
	my $valid_command = qr/
		^\!?		# optional exclamation mark
		([a-zA-Z]+)	# some characters (stored in $1)
		\s*		# optional whitespace
		(.*)		# any remaining characters (stored in $2)
		/x;

	if ($text =~ /$valid_command/)
	{
		do_command($user, $user, $1, $2);
	}
}

sub on_public {
	my ($user, $channel, $text) = @_[ARG0, ARG1, ARG2];
	$user = (split /!/, $user)[0];
	$channel = $channel->[0];
	
	#### LIGHTS HACK ####
	if ($text =~ /banana-chan/) {
		$poe_kernel->post($network, 'kick'=>$channel, $user, "HA! HA! I'm using THE INTERNET!");
	}
	## END LIGHTS HACK ##
	
	if ($LOG == 1) {
		my $ts = scalar(localtime);
		print "[$ts] <$user> $text\n";
	}
	
	$last{$user} = $text;	# add to last database
	$lastwhen{$user} = time();

	my $valid_command = qr/
		^\!		# compulsary exclamation mark
		([a-zA-Z]+)	# some characters (stored in $1)
		\s*		# optional whitespace
		(.*)		# any remaining characters (stored in $2)
		/x;

	if ($text =~ /$valid_command/)
	{
		do_command($user, $channel, $1, $2);
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
	my ($who, $where, $what, $why) = @_;
	if ($who =~ /dong/i) {		# hack for Roseo's stupid thing
		return;
	}
	my $aliaslist = join('|', (keys %aliases));
	
	given ($what) {
		when (/^help/i) {
			cmd_help($why, $where);
		}
		when (/^quit/i) {
			cmd_quit($who, $where, $why);
		}
		when (/^mquit/i) {
			cmd_mquit($who, $where, $why);
		}
		when (/^r(oll)?/i) {
			try_roll($who, $where, $why);
		}
		when (/^join/i) {
			cmd_join($who, $where, $why);
		}
		when (/^alias/i) {
			cmd_alias($who, $where, $why);
		}
		when (/^(seen|last(seen)?)/i) {
			cmd_lastseen($who, $where, $what, $why);
		}
		when (/^botsnack/i) {
			cmd_botsnack($who, $where);
		}
		when (/^[\s!]*$/) {
			$why = $what;
			try_roll($who, $where, $why);
		}
	}
}

sub cmd_lastseen {
	my ($who, $where, $what, $why) = @_;
	if ($why ne $who) {
		foreach $nick (keys %last) {
			my $safenick = $nick;
			$safenick =~ s/\|/\\\|/g;
			if ($why =~ /^$safenick$/i) {
				$why = $nick;
				my $when = $lastwhen{$why};
				$when = time() - $when;
				$what = $last{$why};
				
				if ($when > 60) {
					my $whenm = floor($when / 60);
					my $whens = $when - $whenm * 60;
					if ($whenm > 60) {
						my $whenh = floor($whenm / 60);
						$whenm = floor($whenm - $whenh * 60);
						private_message($where, "I saw $nick $whenh hour" . ($whenh > 1 ? "s" : "") . " and $whenm minutes ago, saying \"\002$what\002\".");
					} else {
						private_message($where, "I saw $nick $whenm minute" . ($whenm > 1 ? "s" : "") . " and $whens seconds ago, saying \"\002$what\002\".");
					}
				} else {
					private_message($where, "I saw $nick $when seconds ago, saying \"\002$what\002\".");
				}
				return;
			}
		}
		private_message($where, "I haven't seen ${why}.");
	}
}

sub cmd_alias {
	my ($who, $where, $why) = @_;
	if ($why eq '') {
		private_message($where, "\003${rollcolour}Currently defined aliases:");
		foreach my $alias (keys %aliases) {
			private_message($where, "\003$dicecolour$alias\t\003$totalcolour$aliases{$alias}");
		}
	} else {
		my ($alias, @definition) = split(/\s/, $why);
		my $definition = "@definition";
		if ($alias eq '') {
			error($where, $who, 9, "The correct usage is !alias <alias> definition, blank definition clears");
		} elsif ($alias =~ /(\d|(\d*)\s*g\s*(\d*)|(\d*)\s*w\s*(\d*)|fudge|^.$)/ && ($who ne $owner)) {
			error($where, $who, 2, "Only $owner can set certain 'dangerous' aliases.");
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
	my ($who, $where) = @_;
	error($where, $who, 0, 'Who do you think I am, foxxbot?');
}

# Quits
sub cmd_quit {
	my ($who, $where, $why) = @_;
	if ($who eq $owner) {
		$exit = 1;
		store(\%last, $lastfile);
		store(\%lastwhen, $whenfile);
		$poe_kernel->post($network, 'quit', $why);
	} else {
		error($where, $who, 45, "Only $owner can order me to quit.");
	}	
}

# WHAT IS THIS I DON'T REMEMBER
sub cmd_mquit {
	my ($who, $where, $why) = @_;
	if ($who eq $owner) {
		$poe_kernel->post($network, 'quit', $why);
	} else {
		error($where, $who, 49, "Only $owner can order me to quit.");
	}	
}

# This should be improved to allow anyone to use it if the bot's not in a channel
sub cmd_join {
	my ($who, $where, $why) = @_;
	if ($who eq $owner) {
		$poe_kernel->post($network, 'part', $channel);
		$channel = $why;
		$poe_kernel->post($network, 'join', $channel);
	} else {
		error($where, $who, 46, "Only $owner can order me to join channels.");
	}	
}

# This could do with some actual documentation
sub cmd_help {
	my ($topic, $recipient) = @_;
	$topic ||= 'general';
	given ($topic) {
		when (/general/i) {
			private_message($recipient, 'usage:');
			private_message($recipient, '  !command <arguments>');
			private_message($recipient, '  /msg bananabot !command <arguments>');
			private_message($recipient, 'commands: alias, help, join, quit, roll, seen');
		}
		when (/alias/i) {
			private_message($recipient, 'Aliases are regular expressions used to add features to the dice language.');
			private_message($recipient, 'To set an alias:');
			private_message($recipient, '  !alias <alias> <definition>');
			private_message($recipient, 'To remove an alias:');
			private_message($recipient, '  !alias <alias>');
			private_message($recipient, 'To view current aliases:');
			private_message($recipient, '  !alias');
		} 
		default {
			error($recipient, -1, "No help available for topic.");
		}
	}
}

sub try_roll {
	my ($who, $where, $why) = @_;
	my @result;
	try {
		@result = cmd_roll($why);
	} catch {
		if (/\[ERROR\](?<error_message>.*)\[ERROR\]/) {
			send_error_message($where, $who, $+{error_message});
		} else {
			warn scalar localtime, "\t$who tried to roll $why and caused an error: $_";
		}
		@result = undef;
	};
	
	foreach my $line (@result) {
		private_message($where, "$who, $line") if defined $line;
	}
}

sub cmd_roll {
	my ($why) = @_;
	my @finaldiceresult;
	my ($j, $q, $notones, $answercolour);
	my $expression = $why;
	
	### INTERPRET MACROS ###
	foreach my $alias (keys %aliases) {
		eval('$expression =~ s/$alias/' . $aliases{$alias} . '/ig;');
	}
	
	### CALCULATE NUMBER OF ROLLS #############################
	(my $line_count, $expression, my $target, my $ones) = calculate_roll_count($expression);

	### SEPERATE BATCH ROLLS #################################
	for my $i (1 .. $line_count) {
		if ($ones > -1) {
			$ones = 0;	# shadowrun check-for-ones
			$notones = 0;
		}
		my @batch = split('&', $expression);
		my $line = '';
		my $successes = 0;
		my $swmishap = 0;
		foreach my $subexpression (@batch) {
	### IMPLEMENT ** OPERATOR #################################
			$subexpression = repeat_rolls($subexpression);
			my $p = $subexpression;						#for pretty-printing
			$subexpression =~ s/".*"//g;
			$p =~ s/"(.*)"/$1/g;
## SUBSTITUTE DIE ROLL RESULTS FOR THE d-EXPRESSIONS ####		7dfh5l
			my @rolls = ($subexpression =~ /(\d*[do]\d*f?[hl]?\d*[hl]?\d*i?|\d*s)/ig);
			for my $roll (@rolls) {
				my $result = 0;
				my $presult = "\003$dicecolour";
				my $orig = $roll;
	### CHECK FOR STAR WARS FAGGOTRY ###
				if ($roll =~ /s/i) {
					($result, $presult, $swmishap) = star_wars($roll, $presult, $swmishap);
				} else {
	### CONFORM TO ROLL FORMAT: a(d|o)blchd, {a,c,d} numbers {b} number or f
				$roll = format_roll($roll);
	### PARSE #################################################
				my ($side_count, $die_count, $individual);
				if ($roll =~ /i/i) {
					$individual = 1;
					$roll =~ s/i//i;
				} else {
					$individual = 0;
				}
				($roll, my $h) = split(/h/i, $roll);
				($roll, my $l) = split(/l/i, $roll);
				my $exploding_dice;
				if ($roll =~ /d/i) {
					($die_count, $side_count) = split(/d/i, $roll);
					$exploding_dice = 0;
				} elsif ($roll =~ /o/) {
					($die_count, $side_count) = split(/o/i, $roll);
					$exploding_dice = 1;
				} elsif ($roll =~ /s/) {
					($die_count, $side_count) = split(/s/i, $roll);
				}
				check_die_count($die_count);
				check_side_count($side_count);

	### ROLL ROLL ROLL ROLL ROLL ROLL ROLL ### BANANABOT ######			
				my (@dice, @sorted_dice);
				
				my $fudge = ($side_count =~ /f/i);
				my $roll_dice = get_roll_function($fudge);

				for (1 .. $die_count) {
					my $finished_rolling = 0;
					until ($finished_rolling) {
						my $die = &$roll_dice($side_count);
						if ($ones > -1 && !$fudge) {
							if ($die == 1) {
								$ones++;
							} else {
								$notones++;
							}
						}
						push(@dice, $die);
						if (!$exploding_dice) {
							$finished_rolling = 1;
						} else {
							if ($fudge) {
								$finished_rolling = 1 unless $die == 1;
							} else { 
								$finished_rolling = 1 unless $die == $side_count;
							}
						}	
					}
				}
				
				if ($h + $l > $die_count) {
 					die "[ERROR]You can't drop more dice than are rolled.[ERROR]";
 				}
				$result = calculate_results(@dice);
				$presult = format_fudge_results($presult, @dice) if $fudge;

 				if (!$fudge) {
 					if ($individual == 0) {
 						$presult .= pad($die_count, $side_count, $result, $line_count);
 					} else {
 						foreach my $die (@dice) {
 							$presult .= pad(1, $side_count, $die, $line_count) . '+';
 						}
 						chop($presult);
 					}
 				}
 				
 				@sorted_dice = sort { $a <=> $b } @dice;
 				unless ($fudge) {
					if ($l > 0) {
						($result, $presult) = drop_low_dice($result, $presult, $l, $side_count, $line_count, @sorted_dice);
					}

					if ($h > 0) {
						($result, $presult) = drop_high_dice($result, $presult, $h, $side_count, $line_count, @sorted_dice);
					}
				}
	 			

	 		}
				$presult .= "\003$rollcolour";
				#replace the $roll with the new total for that $roll
				$subexpression =~ s/$orig/($result)/;
				$p =~ s/$orig/$presult/;
			}
	### MAKE SURE ONLY VALID SYNTAX REMAINS ###################
			my $subexpression = check_syntax($subexpression, $why);
	### EVALUATE THE ANSWER ###################################
			my $answer = eval($subexpression);

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
		
		if ($swmishap) {$line .= "(or mishap)";}
		if ($ones > -1) {
			$line .= "\003${rollcolour}($successes hit" . ($successes != 1 ? "s" : "") . ", " . ($notones <= $ones ? "\003${totalcolour}" : "") . "$ones one" . ($ones != 1 ? "s" : "") . "\003${rollcolour})";
		}
		push (@finaldiceresult, $line);
	}

	return @finaldiceresult;
}

sub check_syntax {
	my ($expression, $why) = @_;
	$expression =~ s/x/\*/gi;	#convenience, allow x for *
	$expression =~ s/\^/\*\*/g;	#convenience, allow ^ for **
	$expression =~ s/p/\+/gi;	#convenience, allow p for +
	unless($expression =~ /^[\d\s\(\)\+\-\*\/\%\.]+$/) {
		die "[ERROR]I don't understand \"\002$why\002\".[ERROR]";
	}
	
	return $expression;
}

sub check_die_count {
	my $die_count = shift;
	if ($die_count < 1) {
		die "[ERROR]I can't roll less than 1 dice.[ERROR]";
	}
	if ($die_count > 39278) {
		die "[ERROR]I can't roll that many dice.[ERROR]";
	}	
}

sub check_side_count {
	my $side_count = shift;
	if ($side_count =~ /\d/ && $side_count > 24789653974) {
		die "[ERROR]A die with $side_count sides would be practically a sphere.[ERROR]";
	}
	if ($side_count !~ /f/i && $side_count < 2) {
		die "[ERROR]$side_count is an invalid number of sides.[ERROR]";
	}
}

sub calculate_roll_count {
	my ($expression) = @_;
	my $target = 0;
	my $line_count = 1;
	my $ones = -1;
	my $fre = qr/
		\s*			# any amount of whitespace
		(?<expression>		# start of grouping (stored in $+{expression})
			\d*		# any number of digits
			\s*		# any amount of whitespace
			(?:		# start of optional (uncaptured) group
				@@?	# one or two '@' marks
				\s*	# any amount of whitespace
				\d*	# any number of digits
			)?		# end of optional group
		)			# end of grouping (stored in $+{expression})
		\s*			# any amount of whitspace
	/x;
	my $non_commas_characters = qr/(?<non_commas>[^,]+)/;
	if ($expression =~ /^${fre}#/) {
		$expression =~ s/${fre}#$non_commas_characters/{
			(my $value, $target, $ones) = and_repeat($+{non_commas}, $+{expression}, $ones);
			$value;
		}/e;
	} elsif ($expression =~ /#$fre$/) {
		$expression =~ s/$non_commas_characters#$fre/{
			(my $value, $target, $ones) = and_repeat($+{non_commas}, $+{expression}, $ones);
			$value;
		}/e;
	}
	if ($expression =~ /,\s*\d+/) {			# a comma, maybe some whitespace, then numbers
		($expression, $line_count) = split(/\s*,\s*/, $expression);
	} elsif ($expression =~ /\d+\s*,/) {		# some numbers, maybe some whitespace, then a comma
		($line_count, $expression) = split(/\s*,\s*/, $expression);
	}
	if ($line_count > 10) {
		$line_count = 10;
	}
	
	return ($line_count, $expression, $target, $ones);
}

sub format_roll {
	my $roll = shift;
	
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
	
	return $roll;
}

sub repeat_rolls {
	my $expression = shift;
	while ($expression =~ /\*\*/) {				
		$expression =~ s/
			([^,\#]+)		# one or more non-comma, non-hash characters (captured to $1)
			\*\*			# two asterisks
			\s*			# some whitespace
			(\d*)			# some digits (captured to $2)
			/roll_repeat($1, $2)	# all replaced with the return value of roll_repeat()
		/ex;
	}
	return $expression;
}

sub star_wars {
	my ($roll, $presult, $swmishap) = @_;
	my ($die, $result);
	# OK, this is a star wars roll - TIME TO GO INSANE >:(
	my ($die_count) = ($roll =~ /\d+/g);
	$die_count ||= 1;
	my $side_count = 6;
	# Roll non-wild dice
	my $highest = 0;
	for my $j (0 .. ($die_count - 2)) {
		$die = int(rand($side_count)) + 1;
		$result += $die;
		$presult .= '+' unless ($j == 0);
		$presult .= "$die";
		if ($die > $highest) {
			$highest = $die;	
		}
	}
	# Wild die WTF
	$presult .= '|';
	$die = int(rand($side_count)) + 1;
	if ($die == 1) {
		$swmishap = 1;
		$result -= $highest;
		$presult .= '-' . $highest;
	} else {
		$result += $die;
		$presult .= $die;
		while ($die == 6) {
			$die = int(rand($side_count)) + 1;
			$result += $die;
			$presult .= '+' . $die;
		}
	}
	
	return ($result, $presult, $swmishap);
}

sub get_roll_function {
	my $fudge = shift;
	if ($fudge) {
		return sub { return (int(rand(3)) -1); };
	}
	return sub {
		my $side_count = shift;
		return int(rand($side_count)) + 1;
	}
}

sub calculate_results {
	my @dice = @_;
	my $result;
	foreach my $die (@dice) {
		$result += $die;
	}
	return $result;
}

sub format_fudge_results {
	my ($presult, @dice) = @_;
	foreach my $die (@dice) {
			if ($die == 1) {$presult .= '+';}
			if ($die == 0) {$presult .= ' ';}
			if ($die == -1) {$presult .= '-';}
	}
	return $presult;
}

sub drop_low_dice {
	my ($result, $presult,  $l, $side_count, $line_count,@sorted_dice) = @_;

	my @dropped = @sorted_dice[0 .. ($l-1)];

	foreach my $die (@dropped) {
		$result -= $die;
		$presult .= '-' . pad(1, $side_count, $die, $line_count);
	}
	return ($result, $presult);
}

sub drop_high_dice {
	my ($result, $presult, $h, $side_count, $line_count, @sorted_dice) = @_;

	my @dropped = @sorted_dice[-$h .. -1];

	foreach my $die (@dropped) {
		$result -= $die;
		$presult .= '-' . pad(1, $side_count, $die, $line_count);
	}
	return ($result, $presult);
}

sub roll_repeat {
	my ($expr, $factor) = @_;
	if ($factor > 128 || $factor < 1) {
		die "[ERROR]Someone's playing silly buggers.[ERROR]";
	}
	my $exprplus = $expr . ' + ';
	return (($exprplus x ($factor - 1)) . $expr);
}



sub and_repeat {
	my ($expr, $factor, $ones) = @_;
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
		die "[ERROR]Someone's playing silly buggers.[ERROR]";
	}
	my $exprplus = $expr . '&';
	return ((($exprplus x ($factor - 1)) . $expr), $target, $ones);
}

sub send_error_message() {
	my ($where, $who, $error_message) = @_;
	private_message($where, "$who,\003$rollcolour Error: $error_message\003");
}

sub pad() {
	my ($die_count, $side_count, $result, $line_count) = @_;
	if ($line_count == 1) {
		return $result;
	}

	my $maxlen;
	if ($side_count =~ /f/i) {
		$maxlen = $die_count;
	} else {
		$maxlen = length ($die_count * $side_count);
	}

	for (my $k = length $result; $k < $maxlen; $k++) {
		$result .= ' ';
	}

	return $result;
}


sub private_message() {
	my ($recipient, $message) = @_;
	$poe_kernel->post($network, 'privmsg'=>$recipient, $message);
}
