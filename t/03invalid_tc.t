use if !eval { require Test::Warn },
	'Test::More', skip_all => 'requires Test::Warn';
use Test::Warn;
use Test::More;

{
	package Foo;
	use Moo;
	use MooX::late;
	has foo => (is => 'ro', isa => 'X Y Z', required => 0);
}

# type constraint should not be checked, so no warning expected
warnings_are {
	my $foo = Foo->new();
} [];

# But this should warn
warnings_like {
	my $foo = Foo->new(foo => 1);
} qr{Type constraint 'X Y Z' not fully enforced \(defined at .+/03invalid_tc\.t:10, package Foo\)};

# But we shouldn't get the same warning again. Too much noise!
warnings_are {
	my $foo = Foo->new(foo => 1);
} [];

done_testing;

=head1 PURPOSE

Check that we get warnings about unrecognisable type constraints, but only
when a value is actually tested against the constraint.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

