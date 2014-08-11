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
                                        datapath => '',
                                        @_)
        or return undef;

    # must have academic year and template objects
    return Webperl::SystemModule::set_error("No Template object available.") if(!$self -> {"template"});
    return Webperl::SystemModule::set_error("No AcademicYear object available.") if(!$self -> {"acyear"});

    $self -> load_course()
        if($self -> {"course"});

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



sub generate {
    my $self = shift;
    my $year = shift;

    $self -> clear_error();

    # Can't do anything if the content isn't loaded
    return $self -> self_error("No course definition information loaded")
        if(!$self -> {"coursedef"});

    my $header = $self -> _build_header($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"column"});
    my $body   = $self -> _build_body($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"column"},
                                      $self -> {"coursedef"} -> {"table"} -> {"rows"} -> {"row"});

    # work out whether the table needs a class definition set
    my $class = "";
    $class = $self -> {"template"} -> load_template("class.tem", {"***class***" -> $self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"class"}})
        if($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"class"});

    my $table = $self -> {"template"} -> load_template("table.tem", {"***class***"  => $class,
                                                                     "***header***" => $header,
                                                                     "***rows***"   => $body});

    return $self -> {"template"} -> load_template("container.tem", {"***course***" => $self -> {"course"},
                                                                    "***style***"  => $self -> {"coursedef"} -> {"table"} -> {"style"},
                                                                    "***table***"  => $table});
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

    my $linkfile = path_join($self -> {"datapath"}, "courses", $course, "links.xml");
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

    my $tablefile = path_join($self -> {"datapath"}, "courses", $course, "table.xml");
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


## @method private $ _build_header($columns)
# Generate a table header row using the specified column data to
# define the values in the header cells.
#
# @param columns A refrence to an array of header columns.
# @return A string containing the header row.
sub _build_header {
    my $self    = shift;
    my $columns = shift;
    my $header  = "";

    # Generate the contents of the header cells.
    foreach my $col (@{$columns}) {
        my $class = "";

        $self -> {"template"} -> load_template("class.tem", "***class***" => $col -> {"class"})
            if($col -> {"class"});

        $header .= $self -> {"template"} -> load_template("header.tem", {"***class***" => $class,
                                                                         "***text***"  => $col -> {"title"}});
    }

    # Wrap the line in a row if there is any content
    $header = $self -> {"template"} -> load_template("row.tem", {"***class***" => '',
                                                                 "***cols***"  => $header})
        if($header);

    return $header;
}


sub _build_body {
    my $self    = shift;
    my $columns = shift;
    my $rows    = shift;
    my $body    = shift;

    # Precalulate the number of columns to save a bit of time later
    my $colcount = scalar(@{$columns});

    # Now process each row in turn, going through the list of columns
    foreach my $rowdata (@{$rows}) {
        my $rowvalues = {};
        my $row = "";

        # allow rows to mark themselves as headers
        my $mode = $rowdata -> {"header"} ? "header.tem" : "cell.tem";

        for(my $colnum = 0; $colnum < $colcount; ++$colnum) {
            # Pull out some values to help with readability
            my $column = $columns -> [$colnum];
            my $data   = $rowdata -> {"data"} -> {$column -> {"id"}};
            my ($span, $class) = ("", "");

            if($data -> {"span"}) {
                $span = $self -> {"template"} -> load_template("colspan.tem", {"***span***" => $data -> {"span"}});
                $colnum += ($data -> {"span"} - 1); # Skip columns to match the span
            }

            $class = $self -> {"template"} -> load_template("class.tem", {"***class***" => $data -> {"class"}})
                if($data -> {"class"});

            # Set the values to substitute
            $rowvalues -> {"text"}  = $data -> {"content"};
            $rowvalues -> {"span"}  = $span;
            $rowvalues -> {"class"} = $class;

            $row .= $self -> {"template"} -> load_template($mode, $rowvalues);
        }

        # Wrap the row up in a row template if needed
        if($row) {
            my $rowclass = "";
            $rowclass = $self -> {"template"} -> load_template("class.tem", {"***class***" => $rowdata -> {"class"}})
                if($rowdata -> {"class"});

            $body .= $self -> {"template"} -> load_template("row.tem", {"***class***" => $rowclass,
                                                                        "***cols***"  => $row});
        }
    }

    return $body;
}

1;