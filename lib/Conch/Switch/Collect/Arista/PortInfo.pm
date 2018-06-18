package Conch::Switch::Collect::Arista::PortInfo;

use strict;
use warnings;

use Conch::Switch::Collect::Arista::Query;

use Exporter 'import';
our @EXPORT = qw( get_portinfo );

sub get_portinfo
{
	my $self = shift;

	return _get_portinfo($self);
}

sub _get_portinfo
{
	my $self = shift;

	my $response = _query_switch_portinfo($self);
	my $portinfo = _parse_switch_portinfo($response);

	return $portinfo;
	
}

sub _query_switch_portinfo
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
		'show interfaces status',
	);

	# Query the switch and get a JSON::RPC::Client object back
	my $response = $self->query(\@cmds);

	# Return the contents of the response
	return $response->content;
}

sub _parse_switch_portinfo
{
	my $data = shift;
	my $portinfo = { };
	my @ports = ( );
	my $id = 1;

	my $ifaces = $data->{result}[0]{interfaceStatuses};
	foreach my $port (sort keys %{$ifaces}) {
		my $poinfo = { };

		$poinfo->{id} = $id;
		$poinfo->{name} = $port;
		$poinfo->{desc} = $ifaces->{$port}{description};
		$poinfo->{speed} = $ifaces->{$port}{bandwidth};
		$poinfo->{duplex} = $ifaces->{$port}{duplex};
		$poinfo->{status} = $ifaces->{$port}{linkStatus};
		$poinfo->{proto_status} = $ifaces->{$port}{lineProtocolStatus};

		if ($ifaces->{$port}{description} eq "") {
			$poinfo->{desc} = undef;
		} else {
			$poinfo->{desc} =
				$ifaces->{$port}{description};
		}

		if ($ifaces->{$port}{interfaceType} eq "Not Present") {
			$poinfo->{type} = undef;
		} else {
			$poinfo->{type} =
				$ifaces->{$port}{interfaceType};
		}

		push @ports, $poinfo;
		$id++;
	}
	$portinfo->{ports} = \@ports;

	return $portinfo;
}

1;
