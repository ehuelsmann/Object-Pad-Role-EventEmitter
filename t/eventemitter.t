#!/usr/bin/perl

use v5.18;
use Object::Pad 0.79;

use Test2::V0;
use Test2::Tools::Compare;
use Test2::Tools::Exception;
use Test2::Tools::Refcount;
use Future;
use Future::Queue;

package test::eventer_superclass {
    class test::eventer_superclass {
        our @EMITS = qw( baz );
    }
}

package test::eventer {
    class test::eventer
        :isa(test::eventer_superclass)
        :does(Object::Pad::Role::EventEmitter) {
        our @EMITS = qw( foo bar );

        method do_emit() {
            $self->emit( 'foo' => 123 );
        }
    }
}

package test::eventer_subclass {
    class test::eventer_subclass :isa(test::eventer) {
        our @EMITS = qw( quux );
    }
}

my $i = test::eventer->new;

is_refcount( $i, 1 );


##############################
#
#  Testing  "on"
#
##############################

my $c = 0;
do {
    my @rv;
    my $subscription = $i->on( foo => sub { $c++; @rv = @_ } );

    is_refcount( $i, 1 );

    $i->do_emit;

    is_refcount( $i, 2 );

    is( $c, 1 );
    is( $rv[0], $i );
    is( $rv[1], 123 );
    is( $i->has_subscribers('foo'), !!1 );
    is( $i->has_subscribers('bar'), !!0 );

    $i->unsubscribe( 'foo', $subscription );
    is( $i->has_subscribers('foo'), !!0 );
};

is_refcount( $i, 1 );

do {
    my $f = Future->new->on_done(sub { $c++ });
    my $subscription = $i->on( foo => $f );
    is( $i->has_subscribers('foo'), !!1 );

    $i->do_emit;

    is( $c, 2 );
    is( $f->is_done, !!1 );

    my @rv = $f->get;
    is( $rv[0], $i );
    is( $rv[1], 123 );
    is( $i->has_subscribers('foo'), !!0 );
};

do {
    my $q = Future::Queue->new;
    my $f = $q->shift;
    my $subscription = $i->on( foo => $q );
    is( $i->has_subscribers('foo'), !!1 );

    $i->do_emit;

    is( $f->is_done, !!1 );

    my @rv = @{$f->get};
    is( $rv[0], $i );
    is( $rv[1], 123 );
    is( $i->has_subscribers('foo'), !!1 );

    $i->unsubscribe( 'foo', $subscription );
    is( $i->has_subscribers('foo'), !!0 );
};

is_refcount( $i, 1 );

do {
    my $f = Future->new;
    my $subscription = $i->on( foo => $f );
    is( $i->has_subscribers('foo'), !!1 );

    $f->cancel;
    is( $i->has_subscribers('foo'), !!0 );
};


##############################
#
#  Testing  "once"
#
##############################

do {
    my @rv;
    my $subscription = $i->once( foo => sub { $c++; @rv = @_ } );

    $i->do_emit;

    is( $c, 3 );
    is( $rv[0], $i );
    is( $rv[1], 123 );
    is( $i->has_subscribers('foo'), !!0 );
};

is_refcount( $i, 1 );



##############################
#
#  Testing  "DEMOLISH"
#
##############################

do {
    my $f = Future->new;
    my $q = Future::Queue->new;
    $i->on( foo => $f );
    $i->on( foo => $q );

    is_refcount( $i, 1 );

    $i = undef;

    is( $f->is_cancelled, !!1 );
    my @rv = $q->shift->get;
    is( scalar(@rv), 0 );
};


##############################
#
#  Testing  "@EMITS"
#
##############################

my $i2 = test::eventer_subclass->new;

ok lives { $i2->has_subscribers( 'foo' ); };
ok lives { $i2->has_subscribers( 'quux' ); };
ok dies { $i->has_subscribers( 'quux' ); };
ok dies { $i->has_subscribers( 'baz' ); };


done_testing;
