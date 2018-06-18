#!/usr/bin/perl

use strict;
use warnings;

use lib './lib';

use JSON::XS;
use HTTP::Tiny;
use Time::Piece;
use Data::Validate::IP;
use Conch::Switch::Collect::Arista;

use Data::Printer;

# GLOBALS
our $state = 'ONLINE';
our $derived = { };
our $inventory = { };
our $envinfo = { };
our $portinfo = { };

my @switches;
if (@ARGV) {
	@switches = @ARGV;
} else {
	print "Usage: $0 <ip> <ip> ...\n";
	exit 1;
}

#
# Loop through each IP, check to make sure if it's a true IP
# or a resolvable hostname, and process it.
#
for my $switch_ip (@switches) {
	my $ip_validator = Data::Validate::IP->new;

	unless ($ip_validator->is_ipv4($switch_ip)) {
		my $packed_ip = inet_aton($switch_ip) ||
			die "could not resolve $switch_ip";
		$switch_ip = inet_ntoa($switch_ip);
	}

	process_switch($switch_ip);
}

exit 0;

#
# Main switch loop
#
sub process_switch
{
	my $ip = shift;

	# Set a default state to ONLINE
	$state = 'ONLINE';

	# For holding calculated/derived data
	$derived = { };

	# Create a HTTP url for talking to the switch
	my $url = "http://" . $ip . ":80";

	# Create an Arista API object
	my $arista = Conch::Switch::Collect::Arista->new(
		'url' => $url,
		'user' => 'conch',
		'password' => 'preflight');

	$envinfo = $arista->get_envinfo;
	$inventory = $arista->get_inventory;
	$portinfo = $arista->get_portinfo;

	my $media = proc_media($inventory);
	my $combinedports = proc_ports($portinfo, $inventory);

	proc_cooling();
	proc_temps();

	my %report = (
		device_type	=> "switch",
		product_vendor	=> "Arista",
		product_name	=> $inventory->{model},
		serial_number	=> $inventory->{serial},
		bios_version	=> $inventory->{os_ver},
		system_uuid	=> $inventory->{system_uuid},
		uptime_since	=> proc_boottime($inventory->{boot_time}),
		state		=> $state,
		processor	=> {
			count	=> 1,
			type	=> "Embedded",
		},
		memory		=> {
			count	=> 1,
			total	=> proc_mem($inventory->{mem_total}),
		},
		fans		=> {
			count	=> scalar $inventory->{fans}->@*,
			units	=> $inventory->{fans},
		},
		temp		=> {
			cpu0	=> $derived->{temp_cpu0},
			cpu1	=> $derived->{temp_cpu1},
			inlet	=> $derived->{temp_inlet},
			exhaust	=> $derived->{temp_exhaust},
			probes	=> $envinfo->{temp},
		},
		psus		=> {
			count	=> scalar $envinfo->{psus}->@*,
			units	=> $envinfo->{psus},
		},
		media		=> $media,
		ports		=> $combinedports->{ports},
	);

	p(%report);

	my $rjson = encode_json(\%report);
	my $response = HTTP::Tiny->new->post(
		"http://127.0.0.1/report" => {
		content => $rjson,
		headers => {
			"Content-Type" => "application/json",
		},
    	},
	);

	print $response->{content},"\n";

	my $json = JSON::XS->new();
	my $msg = decode_json($response->{content});
	my $rep = decode_json($msg->{message});

	if ($rep->{error}) {
		print "API replied with error: " . $rep->{error} . "\n";
		next;
	}

	# If the report API returns healthy, set the switch to validated.
	# This allows the UI to display the proper icon for the switch, etc.
	my $validated = 0;
	if ($rep->{status} eq "pass") {
		$validated = 1;
	}

	my $valid->{'build.validated'} = $validated;

	my $val = HTTP::Tiny->new->post(
		"http://127.0.0.1/pass/device/" .
  	    	$inventory->{serial} .
	    	"/settings/build.validated" => {
			content => encode_json($valid),
			headers => {
				"Content-Type" => "application/json",
			},
		},
	);

	# print "$validated: " . $val->{content},"\n";
}

#
# Arista 7160 seems to have 8GB of RAM, however it:
# 1. Presents it in kilobytes
# 2. Has a portion that's reserved
# The reserved portion seems to be constant, leaving us with 7900080KB.
# If we have that value, we'll assume we have the full 8GB.
#
sub proc_mem
{
	my $mem_total = shift || 0;

	if ($mem_total == 7900080) {
		return 8;
	} else {
		return 0;
	}
}

#
# The Conch validator for temperatures is currently a little rigid
# in what it expects. For this, we must give temperatures for specifc
# things: cpu0, cpu1, inlet and exhaust. Here, we assign those things
# values from actual temperature probes which are analogous in function.
#
sub proc_temps
{
	for my $temp ($envinfo->{temp}->@*) {
		if ($temp->{desc} eq "Cpu temp sensor") {
			$derived->{temp_cpu0} = $temp->{temp_cur};
		} else {
			$derived->{temp_cpu0} = 0;
		}

		if ($temp->{desc} eq "CPU board temp sensor") {
			$derived->{temp_cpu1} = $temp->{temp_cur};
		} else {
			$derived->{temp_cpu1} = 0;
		}

		if ($temp->{desc} eq "Back-panel temp sensor") {
			$derived->{temp_inlet} = $temp->{temp_cur};
		} else {
			$derived->{temp_inlet} = 0;
		}

		if ($temp->{desc} eq "Front-panel temp sensor") {
			$derived->{temp_exhaust} = $temp->{temp_cur};
		} else {
			$derived->{temp_exhaust} = 0;
		}
	}
}

#
# Take the Arista-provided boot time (in Epoch) and convert it
# to an ISO6901 format.
#
sub proc_boottime
{
	my $time = shift;

	my $t = localtime($time);
	return $t->strftime("%F %T%z");
}

#
# We need to combine fan info from 'show inventory' which isn't
# present in fan info from 'show env cooling'. Annoying. This
# includes adding PSU fan info from the latter to the former.
#
sub proc_cooling
{
	for my $efan ($envinfo->{fans}->@*) {
		my $i = 0;
		for my $ifan ($inventory->{fans}->@*) {
			next if ($efan->{location} ne 'fan_tray');
	
			if (($ifan->{slot} - 1) == $efan->{id}) {
				$inventory->{fans}[$i]{status} =
					$efan->{status};
				$inventory->{fans}[$i]{label} =
					$efan->{label};
				$inventory->{fans}[$i]{speed_pct} =
					$efan->{speed_pct};
				$inventory->{fans}[$i]{location} =
					$efan->{location};
				$inventory->{fans}[$i]{id} =
					$efan->{id};
			}
			$i++;
		}

		if ($efan->{location} eq 'psu_fan') {
			my $fan = { };
			$fan->{status} = $efan->{status};
			$fan->{label} = $efan->{label};
			$fan->{speed_pct} = $efan->{speed_pct};
			$fan->{location} = $efan->{location};
			$fan->{id} = $efan->{id};

			push @{$inventory->{fans}}, $fan;
		}
	}
}

#
# Combine port info ('sh int status') with its transceiver info from
# 'sh inventory'. This will one day replace 'media' in the report.
#
sub proc_ports
{
	my $portinfo = shift;
	my $xcvrinfo = shift;

	my @ports = ();
	my $output = { };

	for my $port (@{$portinfo->{ports}}) {
		my $new_port = $port;

		XCVRS: for my $xcvr (@{$xcvrinfo->{xcvrs}}) {
			next unless ($xcvr->{port});
			my $new_xcvr = $xcvr;

			if ($port->{name} eq $xcvr->{port}) {
				delete $new_xcvr->{port};
				delete $new_xcvr->{id};
				$new_port->{xcvr} = $new_xcvr;

				push @ports, $new_port;
				last XCVRS;
			}
		}
	}
	$output->{ports} = \@ports;

	return $output;
}

#
# "The NicsNum validator counts switch ports from the 'media' attribute vs.
# the 'interfaces' list for servers. Generate a 'media' tree for it to use.
sub proc_media
{
	my $xcvrinfo = shift;

	my $output = { };

	for my $xcvr (@{$xcvrinfo->{xcvrs}}) {
		$output->{$xcvr->{port}}{serial} = $xcvr->{serial};
	}

	return $output;
}
