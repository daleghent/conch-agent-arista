package Conch::Switch::Collect::Arista::Inventory;

use strict;
use warnings;

use Data::Printer;
use Conch::Switch::Collect::Arista::Query;

use Exporter 'import';
our @EXPORT = qw( get_inventory );

sub get_inventory
{
	my $self = shift;

	return _get_inventory($self);
}

sub _get_inventory
{
	my $self = shift;

	my $response = _query_switch_inventory($self);
	my $inventory = _parse_switch_inventory($response);

	return $inventory;
	
}

sub _query_switch_inventory
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
		'show version',
		'show inventory',
	);

	# Query the switch and get a JSON::RPC::Client object back
	my $response = $self->query(\@cmds);

	# Return the contents of the response
	return $response->content;
}

sub _parse_switch_inventory
{
	my $data = shift;
	my $inventory = { };
	my $i;

	#
	# Basic chassis info from 'show version'
	#

	$inventory->{os_ver} =
		$data->{result}[0]{version};
	$inventory->{model} =
		$data->{result}[0]{modelName};
	$inventory->{serial} =
		$data->{result}[0]{serialNumber};
	$inventory->{system_mac} =
		$data->{result}[0]{systemMacAddress};
	$inventory->{mem_total} =
		$data->{result}[0]{memTotal};
	$inventory->{boot_time} =
		$data->{result}[0]{bootupTimestamp};

	# Create a system UUID in 8-4-4-4-12 format using the Arista
	# system MAC address
	my $last12 = $inventory->{system_mac};
	$last12 =~ s/://g;
	$inventory->{system_uuid} =
		"00000000-0000-0000-0000-" . $last12;

	#
	# System inventory output from 'show inventory'
	#

	# Fan info - we record this to make sure we have the correct
	# airflow.
	$i = 1;
	my @funits = ( );

	for my $fan (values %{$data->{result}[1]{fanTraySlots}}) {
		my $finfo = { };

		$finfo->{slot} = $i;
		$finfo->{model} = $fan->{name};

		push @funits, $finfo;
		$i++;
	}
	$inventory->{fans} = \@funits;

	# Port info - Information concerning physical ports
	$i = 1;
	my @ports = ( );

	for my $port (values %{$data->{result}[1]{xcvrSlots}}) {
		my $poinfo = { };

		$poinfo->{port} = $i;

		if ($port->{mfgName} eq "Not Present") {
			$poinfo->{xcvr}{mgfr} = undef;
			$poinfo->{xcvr}{model} = undef;
			$poinfo->{xcvr}{hw_rev} = undef;
		} else {
			$poinfo->{xcvr}{mgfr} = $port->{mfgName};
			$poinfo->{xcvr}{model} = $port->{modelName};
			$poinfo->{xcvr}{hw_rev} = $port->{hardwareRev};
		}

		push @ports, $poinfo;
		$i++;
	}
	$inventory->{ports} = \@ports;

	return $inventory;
}

1;
