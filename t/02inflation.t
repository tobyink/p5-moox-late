use strict;
use warnings;
use Test::More;

BEGIN {
	package Local::Class;
	use Moo;
	use MooX::late;
	has foo => (is => 'ro', isa => 'Str', default => 'foo');
};

ok not eval {
	my $obj = Local::Class->new(foo => [])
};

eval {
	require Moose;
	
	my $foo = Local::Class->meta->get_attribute('foo');
	is(
		$foo->type_constraint->name,
		'Str',
	);
};

done_testing;
