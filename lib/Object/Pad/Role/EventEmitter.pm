
use v5.16;  # because of __SUB__
use Feature::Compat::Try;
use Object::Pad 0.79;

package Object::Pad::Role::EventEmitter;
role Object::Pad::Role::EventEmitter;

use Scalar::Util qw(blessed);
use Scope::Guard;


field %subscribers;
field $_guard; # Emulate DEMOLISH

method emit( $event, @args ) {
    if (exists $subscribers{$event}) {
        for my $cb (@{$subscribers{$event}}) {
            $cb->[0]->( $self, @args );
        }
    }
}

method has_subscribers( $event ) {
    return ((exists $subscribers{$event})
            and (@{$subscribers{$event}} > 0));
}

method on( $event, $subscriber ) {
    $subscribers{$event} //= [];
    if (not $_guard) { # Emulate DEMOLISH
        $_guard = Scope::Guard->new(
            sub {
                for my $event (keys %subscribers) {
                    # make sure all futures are cancelled
                    # and queues are finished
                    for my $item (@{$subscribers{$event}}) {
                        $item->[1]->();
                    }
                }
            })
    }

    my $item;
    if (blessed $subscriber) {
        if ($subscriber->isa("Future")) {
            $item = [
                sub {
                    my ($self) = @_;
                    $subscriber->done( @_ );
                    $self->unsubscribe( $event, __SUB__ );
                },
                sub { $subscriber->cancel; }
                ];
        }
        else { # this must be a Future::Queue
            $item = [
                sub {
                    my ($self) = @_;
                    try {
                        $subscriber->push( [ @_ ] );
                    }
                    catch ($e) {
                        # the queue was finished; unsubscribe
                        $self->unsubscribe( $event, __SUB__ );
                    }
                },
                sub { $subscriber->finish; }
                ];
        }
    }
    else {
        $item = [ $subscriber, sub { } ];
    }
    push @{$subscribers{$event}}, $item;
    return $item->[0];
}

method once( $event, $subscriber ) {
    return $self->on(
        $event,
        sub {
            my ($self) = @_;
            $subscriber->( @_ );
            $self->unsubscribe( $event, __SUB__ );
        });
}

method unsubscribe( $event, $subscription=undef ) {
    return unless exists $subscribers{$event};

    if ($subscription) {
        my $idx;
        my $items = $subscribers{$event};
        ($items->[$_]->[0] == $subscription) and ($idx = $_), last for $#$items;

        if (defined $idx) {
            my $deleted = splice @$items, $idx, 1, ();
            $deleted->[1]->();
        }
        delete $subscribers{$event} unless @$items;
    }
    else {
        for my $item (@{$subscribers{$event}}) {
            $item->[1]->();
        }
        delete $subscribers{$event};
    }

    return;
}

1;

__END__

=head1 NAME

Object::Pad::Role::EventEmitter - A role for Object::Pad classes to emit events

=head1 SYNOPSIS

  use Object::Pad;
  use Object::Pad::Role::EventEmitter;

  package MyObject;
  class MyObject :does(Object::Pad::Role::EventEmitter);

  method foo($a) {
    $self->emit(foo => $a);
  }

  1;

  package main;

  use MyObject;
  use Future;
  use Future::Queue;

  my $i = MyObject->new;

  # subscribe to an event once:
  $i->once(foo => sub { say "Hello" });

  # or with a future:
  my $f = Future->new->on_done(sub { say "Hello" });
  $i->on(foo => $f);

  # subscribe to multiple events:
  my $subscription = $i->on(foo => sub { say "Hello" });

  # or on a queue:
  my $q = Future::Queue->new;
  my $subscription_q = $i->on(foo => $q);

  # then unsubscribe:
  $i->unsubscribe( $subscription );
  $i->unsubscribe( $subscription_q );

  # or finish the queue (unsubscribes upon the next event):
  $q->finish;


=head1 DESCRIPTION

This role adds to a class the capability to emit events to subscribers.
Interested subscribers can provide a code reference, a L<Future::Queue>
or a L<Future> to receive events.

=head1 METHODS

=head2 on

  my $subscription = $obj->on( foo => sub { ... } );
  my $subscription = $obj->on( foo => $f );
  my $subscription = $obj->on( foo => $q);

Subscribes to notifications of the named event.  The event consumer can be
a coderef, L<Future> or L<Future::Queue>. In case it's a C<Future>, the
consumer will be unsubscribed after a single event.

Returns a C<$subscription> which can be used to unsubscribe later.

=head2 once

  my $subscription = $obj->once( foo => sub { ... } );

Subscribes to a single notification of teh named event.  This function does
not make sense for the Future and Future::Queue subscribers, because Futures
are single-notification anyway and Future::Queues are much more easily
replaced with Futures for single notifications.

=head2 emit

  $obj->emit( $event_name, $arg1, $arg2, ...)

Send the event to subscribers.  If the subscriber is a coderef, the
function is called with the object as the first argument and the values
of C<$arg1, $arg2, ...> as further arguments.  If the subscriber is a
Future, it resolves with the same values as passed to the callback.  If
the subscriber is a Future::Queue, an arrayref is put in the queue with
the elements of the array being the values as passed to the callback.

  # callback style:
  $sink->( $obj, $arg1, $arg2, ... );

  # Future style:
  $f->done( $obj, $arg1, $arg2, ... );

  # Future::Queue style:
  $q->push( [ $obj, $arg1, $arg2, ... );

=head2 has_subscribers

  my $bool = $obj->has_subscribers( 'foo' );

Checks if the named event has subscribers.

=head2 unsubscribe

  $obj->unsubscribe( 'foo' );
  $obj->unsubscribe( foo => $subscription );

Remove all subscribers from the named event (when no subscription argument
is given) or remove the specific subscription.

Any pending futures will be cancelled upon unsubscription.  Queues will
be finished.

When an object goes out of scope, this function is used to cancel any active
subscriptions.

=head1 AUTHOR

=over 4

=item * C<< Erik Huelsmann <ehuels@gmail.com> >>

=back

Inspired on L<Role::EventEmitter> by Dan Book, which is itself adapted
from L<Mojolicious>.  This module and its tests are implemented from scratch.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2023 by Erik Huelsmann.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.
