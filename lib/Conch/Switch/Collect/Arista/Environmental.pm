package Conch::Switch::Collect::Arista::Environmental;

use strict;
use warnings;

use POSIX qw( ceil );
use Conch::Switch::Collect::Arista::Query;

use Exporter 'import';
our @EXPORT = qw( get_envinfo );

sub get_envinfo
{
	my $self = shift;

	return _get_envinfo($self);
}

sub _get_envinfo
{
	my $self = shift;

	my $response = _query_switch_envinfo($self);
	my $data = _parse_switch_envinfo($response);

	return $data;
}

sub _query_switch_envinfo
{
	my $self = shift;

	# For Arista inventory needs, we requrire the results of the
	# following commands. Additional commands may be added as array
	# members. The output of each command is contained in its own
	# JSON array in the response.
	#
	# Ordering of commands here is important, as the results array
	# in the reply is ordered in the same way. The parser will assume
	# that output at position 0 is the output of 'show version', and
	# position 1 will be the output of 'show inventory', etc.
	my @cmds = (
		'show environment cooling',
		'show environment power detail',
		'show environment temperature detail',
	);

	# Query the switch and get a JSON::RPC::Client object back
	my $response = $self->query(\@cmds);

	# Return the contents of the response
	return $response->content;
}

sub _parse_switch_envinfo
{
	my $data = shift;

	my $output = { };
	$output = _parse_cooling($data, $output);
	$output = _parse_power($data, $output);
	$output = _parse_temperature($data, $output);

	return $output;
}

#
# Parse 'show env cooling' data. We look for individual fans in fan trays
# as well as any fans reported in PSUs. All of these are collected under
# $output->{fans}.
#
sub _parse_cooling
{
	my $data = shift;
	my $output = shift;
	my @fans = ( );
	my $id = 0;

	# Exit early if there are no fan trays
	return $output if (! $data->{result}[0]{fanTraySlots});

	# Iterate over each fan tray and extract per-fan data
	for my $fantray (@{$data->{result}[0]{fanTraySlots}}) {
		for my $fan (@{$fantray->{fans}}) {
			my $faninfo = { };

			$faninfo->{status} = $fan->{status};
			$faninfo->{speed_pct} = $fan->{actualSpeed};
			$faninfo->{label} = $fan->{label};
			$faninfo->{location} = 'fan_tray';
			$faninfo->{id} = $id;

			push @fans, $faninfo;
			$id++;
		}
	}

	# Exit early if there are no PSUs with fans present
	if (! $data->{result}[0]{powerSupplySlots}) {
		my @sorted = sort { $a->{id} <=> $b->{id} } @fans;
		$output->{fans} = \@sorted;

		return $output;
	}

	# Iterate over any PSU objects and pick out any fan data
	for my $psufanset (@{$data->{result}[0]{powerSupplySlots}}) {
		for my $fan (@{$psufanset->{fans}}) {
			my $faninfo = { };

			$faninfo->{status} = $fan->{status};
			$faninfo->{speed_pct} = $fan->{actualSpeed};
			$faninfo->{label} = $fan->{label};
			$faninfo->{location} = 'psu_fan';
			$faninfo->{id} = $id;

			push @fans, $faninfo;
			$id++;
		}
	}

	my @sorted = sort { $a->{id} <=> $b->{id} } @fans;
	$output->{fans} = \@sorted;

	return $output;
}

#
# Parse 'show env power detail' data. We look for individual PSUs and
# store data about each under $output->{psus}. The PSUs are not preented
# in a JSON array, so we must not their Slot ID using the key.
#
sub _parse_power
{
	my $data = shift;
	my $output = shift;
	my @psus = ( );

	for my $psu (keys %{$data->{result}[1]{powerSupplies}}) {
		my $pinfo = $data->{result}[1]{powerSupplies}{$psu};
		my $psuinfo = { };

		$psuinfo->{id} = $psu;
		$psuinfo->{state} = $pinfo->{state};
		$psuinfo->{model} = $pinfo->{modelName};
		$psuinfo->{mfgr} = $pinfo->{mfrId};
		$psuinfo->{mfgr_rev} = $pinfo->{mfrRevision};
		$psuinfo->{mfgr_model} = $pinfo->{mfrModel};
		$psuinfo->{firmware_1} = $pinfo->{priFirmware};
		$psuinfo->{firmware_2} = $pinfo->{secFirmware};
		$psuinfo->{volts_in} = $pinfo->{inputVoltage};
		$psuinfo->{amps_in} = $pinfo->{inputCurrent};
		$psuinfo->{watts_in} = $pinfo->{inputPower};
		$psuinfo->{volts_out} = $pinfo->{outputVoltage};
		$psuinfo->{amps_out} = $pinfo->{outputCurrent};
		$psuinfo->{watts_out} = $pinfo->{outputPower};

		($psuinfo->{serial}) = $pinfo->{specificInfo} =~
			m/MFR_SERIAL\s\(\w+\):\s(\w+)/g;

		push @psus, $psuinfo;
	}
	my @sorted = sort { $a->{id} <=> $b->{id} } @psus;
	$output->{psus} = \@sorted;

	return $output;
}

#
# Parse 'show env temperature detail' data. We look for system temperature
# probes ("chassis" probes) as well as any temperature probes present in
# PSUs ("psu" probes).
#
sub _parse_temperature
{
	my $data = shift;
	my $output = shift;
	my @tprobes = ( );
	my $id = 0;

	# Exit early if there are no temperature probes
	return $output if (! $data->{result}[2]{tempSensors});

	# Iterate over temperature probes and record their data
	for my $tprobe (@{$data->{result}[2]{tempSensors}}) {
		my $tinfo = { };

		$tinfo->{id} = $id;
		$tinfo->{name} = $tprobe->{name};
		$tinfo->{desc} = $tprobe->{description};
		$tinfo->{location} = 'chassis';
		$tinfo->{status} = $tprobe->{hwStatus};
		$tinfo->{temp_cur} = ceil($tprobe->{currentTemperature});
		$tinfo->{temp_oh} = ceil($tprobe->{overheatThreshold});
		$tinfo->{temp_crit} = ceil($tprobe->{criticalThreshold});
		$tinfo->{alert_count} = $tprobe->{alertCount};
		$tinfo->{alert_cur} = $tprobe->{inAlertState};

		push @tprobes, $tinfo;
		$id++;
	}

	# Exit early if there are no PSUs with temperature probes
	if (! $data->{result}[2]{powerSupplySlots}) {
		my @sorted = sort { $a->{id} <=> $b->{id} } @tprobes;
		$output->{temp} = \@sorted;

		return $output;
	}

	# Iterate over PSUs which have temperature probes
	for my $psu (@{$data->{result}[2]{powerSupplySlots}}) {
		for my $tprobe (@{$psu->{tempSensors}}) {
			my $tinfo = { };

			$tinfo->{id} = $id;
			$tinfo->{name} = $tprobe->{name};
			$tinfo->{desc} = $tprobe->{description};
			$tinfo->{location} = 'psu';
			$tinfo->{status} = $tprobe->{hwStatus};
			$tinfo->{temp_cur} = ceil($tprobe->{currentTemperature});
			$tinfo->{temp_oh} = ceil($tprobe->{overheatThreshold});
			$tinfo->{temp_crit} = ceil($tprobe->{criticalThreshold});
			$tinfo->{alert_count} = $tprobe->{alertCount};
			$tinfo->{alert_cur} = $tprobe->{inAlertState};

			push @tprobes, $tinfo;
			$id++;
		}
	}

	my @sorted = sort { $a->{id} <=> $b->{id} } @tprobes;
	$output->{temp} = \@sorted;

	return $output;
}

1;
