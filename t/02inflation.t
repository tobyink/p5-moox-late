=head1 PURPOSE

Check that our type constraints are correctly inflated to Moose type
constraints.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012-2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

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
