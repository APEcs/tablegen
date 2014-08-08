## @file
# This file contains the implementation of the Academic Year model
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class
#
package AcademicYear;

use v5.12;
use base qw(Webperl::SystemModule);
use Webperl::Utils qw(hash_or_hashref);
use DateTime;
use Data::Dumper;
use XML::Simple;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Construct a new AcademicYear model object to handle loading of year
# data and lookup of week information.
#
# @param args A hash of values to initialise the object with.
# @return A new AcademicYear object.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(minimal    => 1, # minimal tells SystemModule to skip object checks
                                        fix_breaks => 1, # if set to zero, adjustments to break start/end times are not made
                                        yearfile   => '',
                                        @_)
        or return undef;

    # load the year file if possible
    $self -> load_yearfile()
        if($self -> {"yearfile"});

    return $self;
}


# ============================================================================
#  Year loader and access

## @method $ load_yearfile($filename)
# Attempt to populate the AcademicYear object's information about when semesters
# and breaks start and end for each year based on the information in the
# specified year file.
#
# @param yearfile The name of the year file to load the academic year information
#                 from. If not specified, the yearfile set when creating the
#                 object is used instead.
# @return true on success, undef on error. If this returns undef, but a previous
#         call returned true, the last successfully loaded information is not
#         cleared.
sub load_yearfile {
    my $self     = shift;
    my $filename = shift || $self -> {"yearfile"};

    $self -> clear_error();

    return $self -> self_error("No year file specified")
        if(!$filename);

    my $yeardata = eval { XMLin($filename, KeepRoot => 0, ForceArray => [ 'break' ], KeyAttr => [ 'id' ]) };
    return $self -> self_error("Year file loading failed: $@")
        if($@);

    print "Data: ".Dumper($yeardata)."\n";

    $self -> {"yeardata"} = $yeardata;
    $self -> {"yearfile"} = $filename;

    # Now fix up all the dates
    return $self -> _convert_yeardata_dates();
}



## @method $ weeks(%args)
# Fetch the list of weeks for the specified semester in a year
#
# @param arg A hash, or reference to a hash, of argument to control the behaviour
#            of the function.
# @return A reference to an array of week hashes on success, undef on error.
sub weeks {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    # Year must be specified and valid
    return $self -> self_error("No academic year selected")
        if(!$args -> {"year"});

    my $yeardata = $self -> {"yeardata"} -> {"year"} -> {$args -> {"year"}}
        or return $self -> self_error("Unknown academic year ".$args -> {"year"}." selected");

    # As must the semester
    return $self -> self_error("No semester selected")
        if(!$args -> {"semester"});

    my $semdata = $yeardata -> {"semester"} -> {$args -> {"semester"}}
        or return $self -> self_error("Unknown semester ".$args -> {"semester"}." selected");

    # Start off at the beginning of the semester
    my $currdate = $semdata -> {"start"} -> clone();

    my @days = ();
    my $week = 0;
    while($currdate < $semdata -> {"end"}) {
        my $break = $self -> _in_break($currdate, $semdata);

        # Not in a break, treat each week individually
        if(!$break) {
            if($args -> {"initial_welcome"} && $currdate == $semdata -> {"start"}) {
                push(@days, {"id"   => $week, # Welcome week gets week number 0
                             "name" => "Welcome Week",
                             "date" => $currdate -> clone()});
            } else {
                push(@days, {"id"   => ++$week,
                             "name" => "Week $week",
                             "date" => $currdate -> clone()});
            }
            $currdate -> add(weeks => 1);

        # Breaks just report the break, including start/end.
        } else {
            push(@days, {"id"    => $break -> {"id"},
                         "break" => $break,
                         "name"  => $break -> {"name"}});

            # skip straight to the end
            $currdate = $break -> {"end"} -> clone();

            $currdate -> add(days => 1) if($self -> {"fix_breaks"});
        }
    }

    return \@days;
}


# ============================================================================
#  Internal implementation stuff


## @method private $ _convert_yeardata_dates(void)
# Convert the date fields in the yeardata to DateTime objects if they are not
# already in that format.
#
# @return true on success, undef on error
sub _convert_yeardata_dates {
    my $self  = shift;
    my $years = $self -> {"yeardata"} -> {"year"}; # For laziness.

    # Years are hashed by their ID
    foreach my $year (keys(%{$years})) {

        # Years can contain multiple semesters
        foreach my $semester (keys(%{$years -> {$year} -> {"semester"}})) {
            my $semref = $years -> {$year} -> {"semester"} -> {$semester};

            # Convert the start and end dates for the semester
            $semref -> {"start"} = $self -> _convert_date($semref -> {"start"})
                or return undef;
            $semref -> {"end"}   = $self -> _convert_date($semref -> {"end"}, 1)
                or return undef;

            # Semesters may contain breaks
            foreach my $break (keys(%{$semref -> {"break"}})) {
                my $breakref = $semref -> {"break"} -> {$break};

                $breakref -> {"start"} = $self -> _convert_date($breakref -> {"start"})
                    or return undef;
                $breakref -> {"end"}   = $self -> _convert_date($breakref -> {"end"}, 1)
                    or return undef;

                # Store the break id for ease of access later
                $breakref -> {"id"} = $break;

                # Fix up start and end if needed
                if($self -> {"fix_breaks"}) {
                    $breakref -> {"start"} -> add(days => 1);
                    $breakref -> {"end"} -> subtract(days => 1);
                }
            }
        }
    }

    return 1;
}


## @method private $ _convert_date($date, $end)
# If the specified date is not a DateTime object, attempt to use it as an
# ISO8601 date to create a DateTime object from.
#
# @param date The date to create a DateTime object from.
# @param end  If true, the time is set to 23:59:59 rather than 00:00:00.
# @return A reference to a DateTime object on success, undef on error.
sub _convert_date {
    my $self = shift;
    my $date = shift;
    my $end  = shift;

    $self -> clear_error();

    # Pass DateTime objects through untouched
    return $date
        if(ref($date) && $date -> isa("DateTime"));

    return $self -> self_error("Illegal value passed to _convert_date")
        if(ref($date));

    my ($year, $mon, $day) = $date =~ /^(\d{4})-?(\d{2})-?(\d{2})$/;
    return $self -> self_error("Unable to parse date string from '$date'")
        if(!$year || !$mon || !$day);


    my $datetime = eval { DateTime -> new(year => $year, month => $mon, day => $day) };
    return $self -> self_error("Unable to create DateTime object: $@")
        if($@);

    $datetime -> set(hour => 23, minute => 59, second => 59)
        if($end);

    return $datetime;
}


## @method private $ _in_break($date, $semester)
# Determine whether the specified date fails within a break in the
# specified semester, and return the break data if it does.
#
# @param date     The date to check.
# @param semester A reference to the semester information
# @return A reference to the break hash if the date is in a break,
#         undef otherwise.
sub _in_break {
    my $self     = shift;
    my $date     = shift;
    my $semester = shift;

    foreach my $break (keys(%{$semester -> {"break"}})) {
        my $breakdata = $semester -> {"break"} -> {$break};

        # If the data is inside the break date range, return the break
        return $breakdata
            if($date >= $breakdata -> {"start"} && $date <= $breakdata -> {"end"});
    }

    return undef;
}


1;
