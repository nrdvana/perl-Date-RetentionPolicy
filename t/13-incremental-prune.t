#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok( 'Date::RetentionPolicy' ) or BAIL_OUT;

=head1 DESCRIPTION

This test simulates a backup schedule running for a year.  A snapshot is made
every six hours, with up to thirty minutes of deterministic scheduling jitter,
and the accumulated snapshots are pruned after every run.  Each simulated run
uses the same reference date that C<reference_date_or_default> would calculate:
the start of the following day.

The final assertion guards against repeated pruning gradually discarding the
weekly snapshots.  Once the simulation is complete, at least nine snapshots
from the part of the weekly retention window older than three months must
remain.

=cut

my @retention_policy= (
	{ interval => { hours => 6 }, history => { months =>  1 } },
	{ interval => { days  => 1 }, history => { months =>  3 } },
	{ interval => { days  => 7 }, history => { months => 12 } },
);

my $start= DateTime->new(year => 2017, month => 1, day => 1, time_zone => 'UTC');
my $end= $start->clone->add(years => 1);
my $rp= new_ok( 'Date::RetentionPolicy', [
	retain => \@retention_policy,
	auto_sync => 1,
] );

my @snapshots;
my $iteration= 0;
for (
	my $scheduled= $start->clone;
	DateTime->compare($scheduled, $end) < 0;
	$scheduled->add(hours => 6)
) {
	# Deterministic jitter covering the range from 30 minutes early to late.
	my $jitter= (($iteration++ * 7919) % 3601) - 1800;
	my $snapshot= $scheduled->epoch + $jitter;
	push @snapshots, $snapshot;
	# Match reference_date_or_default for the time of this simulated run.
	my $reference_date= $scheduled->clone
		->add(days => 1, seconds => -1)
		->truncate(to => 'day');
	$rp->reference_date($reference_date);
	$rp->prune(\@snapshots);
}

my $three_month_cutoff= $end->clone->subtract(months => 3)->epoch;
my @older_than_three_months= grep { $_ < $three_month_cutoff } @snapshots;
cmp_ok(
	scalar @older_than_three_months,
	'>=',
	9,
	'at least 9 snapshots older than three months survive incremental pruning',
);

done_testing;
