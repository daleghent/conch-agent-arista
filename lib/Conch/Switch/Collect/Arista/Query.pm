package Conch::Switch::Collect::Arista::Query;

use strict;
use warnings;

use JSON::RPC::Client;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( query );

sub query
{
	my ($self, @cmds) = @_;

	my $url = $self->{url};
	my $user = $self->{user};
	my $passwd = $self->{password};

	if (! $user || ! $passwd) {
		die "Requires user and password.";
	}

	if (! @cmds) {
		die "A command must be given!";
	}

	$url = $url . "/command-api";

	my $client = new JSON::RPC::Client;
	my $host;

	if ($url =~ m/http[^:]*:\/\/([^\/]+)\//) {
		$host = $1;
	} else {
		die ("couldn't extract hostname from url");
	}

	# Set LWP to ignore SSL cert hostname mismatches
	$client->ua->ssl_opts(verify_hostname => 0);

	# Set our HTTP Basic Auth parameters
	$client->ua->credentials($host, 'COMMAND_API_AUTH', $user, $passwd);

	# Create JSON-RPC object which conntains the EOS commands we
	# want to run.
	my $callobj = {
		jsonrpc => "2.0",
		method => "runCmds",
		params => {
			version => 1,
			cmds => @cmds
		},
		id => "jfeapi"
	};

	my $data = $client->call($url , $callobj);

	if ($data) {
		if ($data->is_error) {
			return $data->error_message->{code} .": " .
				$data->error_message->{message};
		} else {
			return $data;
		}
	} else {
		die ("connection error: " . $client->status_line);
	}

	die ("unexpected condition");
}

1;
