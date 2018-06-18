package Conch::Switch::Collect::Arista::Version;

use strict;
use warnings;

use Conch::Switch::Collect::Arista::Query;

use Exporter 'import';
our @EXPORT = qw( get_version );

sub get_version
{
	my $self = shift;

	return _get_version($self);
}

sub _get_version
{
	my $self = shift;

	my $response = _query_switch_version($self);
	my $inventory = _parse_switch_version($response);

	return $inventory;
	
}

sub _query_switch_version
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
	);

	# Query the switch and get a JSON::RPC::Client object back
	my $response = $self->query(\@cmds);

	# Return the contents of the response
	return $response->content;
}

sub _parse_switch_version
{
	my $data = shift;
	my $version = { };

	#
	# Basic version info from 'show version'
	#

	$version->{version} =
		$data->{result}[0]{version};
	$version->{serialNumber} =
		$data->{result}[0]{serialNumber};

	return $version;
}

1;
