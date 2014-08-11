## @file
# This file contains the implementation of the table generator library
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
package TableGen;

use v5.12;
use base qw(Webperl::SystemModule);
use Webperl::Utils qw(path_join);
use XML::Simple;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Construct a new TableGen model object to handle loading of year
# data and lookup of week information.
#
# @param args A hash of values to initialise the object with.
# @return A new TableGen object.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(minimal  => 1, # minimal tells SystemModule to skip object checks
                                        course   => '',
                                        basepath => '',
                                        @_)
        or return undef;

    # must have an academic year object
    return Webperl::SystemModule::set_error("No AcademicYear object available.") if(!$self -> {"acyear"});

    return $self;
}

# ============================================================================
#  Course loader and access

## @method $ load_course($course)
# Load the table and file definitions for the specified file.
#
#
sub load_course {
    my $self   = shift;
    my $course = shift || $self -> {"course"};

    $self -> clear_error();

    return $self -> self_error("No course specified")
        if(!$course);

    my $definitions = { };
    $definitions -> {"table"} = $self -> _load_table_data($course)
        or return undef;

    $definitions -> {"links"} = $self -> _load_link_data($course)
        or return undef;

    $self -> {"course"} = $course;
    $self -> {"coursedef"} = $definitions;

    return 1;
}


# ============================================================================
#  Internal implementation

## @method private $ _load_link_data($course)
# Load the link definitions from the links.xml file associated with the specified
# course.
#
# @param course The name of the course to load the data for
# @return A reference to a hash containing the link data on success, undef on error.
sub _load_link_data {
    my $self   = shift;
    my $course = shift;

    $self -> clear_error();

    my $linkfile = path_join($self -> {"basepath"}, "courses", $course, "links.xml");
    my $linkdata = eval { XMLin($linkfile, KeepRoot => 0, ContentKey => '-content', KeyAttr => [ 'name' ]) };
    return $self -> self_error("Link file loading failed for $course: $@")
        if($@);

    return $linkdata;
}


## @method private $ _load_table_data($course)
# Load the table definition from the table.xml file associated with the specified
# course.
#
# @param course The name of the course to load the data for
# @return A reference to a hash containing the table definition on success, undef
#         on error.
sub _load_table_data {
    my $self   = shift;
    my $course = shift;

    $self -> clear_error();

    my $tablefile = path_join($self -> {"basepath"}, "courses", $course, "table.xml");
    my $tabledata = eval { XMLin($tablefile, KeepRoot => 0, ForceArray => [ 'column' ], KeyAttr => { 'column' => '', data => 'for' }) };
    return $self -> self_error("Table definition loading failed for $course: $@")
        if($@);

    # The $tabledata -> {"rows"} -> {"row"} value is an arrayref, there may need
    # to be a lookup table too, so construct one
    foreach my $row (@{$tabledata -> {"rows"} -> {"row"}}) {
        $tabledata -> {"rows"} -> {"rowhash"} -> {$row -> {"semester"}} -> {$row -> {"week"}} = $row;
    }

    return $tabledata;
}

1;