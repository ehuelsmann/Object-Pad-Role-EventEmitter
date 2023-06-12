#!/usr/bin/perl

use Object::Pad 0.79;

use Test2::V0;
use Test2::Tools::Compare;
use Test2::Tools::Refcount;
use Future;
use Future::Queue;

package test::eventer {
    class test::eventer :does(Object::Pad::Role::EventEmitter) {
        method do_emit() {
            $self->emit( 'foo' => 123 );
        }
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

done_testing;
