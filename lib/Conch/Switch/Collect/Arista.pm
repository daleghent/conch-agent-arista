package Conch::Switch::Collect::Arista;

use strict;
use warnings;

use Conch::Switch::Collect::Arista::Query;
use Conch::Switch::Collect::Arista::Inventory;
use Conch::Switch::Collect::Arista::PortInfo;
use Conch::Switch::Collect::Arista::Environmental;

sub new
{
	my $class = shift;
	my $self = {@_};

	bless($self, $class);
	return $self;
}

1;
