#! /usr/bin/env python
# -*- coding: utf-8 -*-

"""
This program matches the two given grids and writes the output into
an file.

usage:
python match_grid.py grid_infile header_or_gridfile grid_outfile

Arguments:
    1. The source grid to be enlarged (grid_infile)
    2. The target grid which could also be an header file (header_or_gridfile)
    3. An output file (grid_outfile)

Written:
    David Schaefer, November 2013
    Modified, Nov 2015: Stephan Thober - included netCDF file format
"""

import sys,os
from math import floor, ceil

class AsciiGrid(object):
    
    def __init__(self, filename, ncfile=None, headerlines=6):
        self._filename = filename
        self._headerlines = headerlines
        self._nodata_value = None
        self._ncfile = ncfile
        self.read()
        if ncfile != None:
            self.readnc()

    @property
    def nodata_value(self):
        return self._nodata_value

    @nodata_value.setter
    def nodata_value(self,value):
        try:
            self.data = self.data.replace(str(self._nodata_value),str(value))
        except AttributeError:
            pass
        self._nodata_value = value
            
        
    def read(self):
        with open(self._filename,"r") as f:
            # correct for line feed and decimal delimiter
            data = f.read().replace("\r\n","\n").replace(",",".").strip() + "\n"
            
        start = 0       
        for i in range(self._headerlines):            
            end = data.find("\n",start)
            k,v = [e.strip().lower() for e in data[start:end].split()]
            try:
                self.__setattr__(k,int(v))
            except ValueError:
                self.__setattr__(k,float(v))
            start = end + 1
        self.data = data[start:].strip()

        # Ensure that the grid origin is definied as the lower-left corner
        # of the lower-left cell
        try:
            self.yllcorner = float(self.yllcenter) - float(self.cellsize)/2
            self.xllcorner = float(self.xllcenter) - float(self.cellsize)/2
        except AttributeError:
            pass

    def readnc(self):
        from ufz import readnc
        # read netcdf variable, array and attributes
        self.ncvar = self._ncfile.split('/')[-1].split('.')[0]
        self.ncarr = readnc(self._ncfile, var=self.ncvar)
        self.ncatt = readnc(self._ncfile, var=self.ncvar, attributes=True)
        self.nctime = readnc(self._ncfile, var='time')
        self.nctimeatt = readnc(self._ncfile, var='time', attributes=True)

        
    def getBbox(self):
        return {"ymin":self.yllcorner,
                "ymax":self.yllcorner + self.nrows * self.cellsize,
                "xmin":self.xllcorner,
                "xmax":self.xllcorner + self.ncols * self.cellsize}

    
    def write(self,filename):
        if hasattr(self, 'ncarr'):
            from ufz import dumpnetcdf
            from time import asctime
            # set file attributes
            fileatt = {'ncols': self.ncols, 'nrows': self.nrows, 'xllcorner': self.xllcorner, 'yllcorner': self.yllcorner,
                       'cellsize': self.cellsize, 'NODATA_value': self.nodata_value, 'history': 'Created ' + asctime()}
            # add time to netcdf file
            dumpnetcdf(filename, dims=['time'], fileattributes=fileatt, time=(self.nctime, self.nctimeatt))
            # write netcdf data set
            eval("dumpnetcdf(filename, dims=['time', 'yc', 'xc'], create=False, " + self.ncvar + " = (self.data, self.ncatt))")
        else:
            # write ascii dataset
            with open(filename,"w") as f:
                f.write("ncols\t{:}\n".format(str(self.ncols)))
                f.write("nrows\t{:}\n".format(str(self.nrows)))
                f.write("xllcorner\t{:}\n".format(str(self.xllcorner)))
                f.write("yllcorner\t{:}\n".format(str(self.yllcorner)))
                f.write("cellsize\t{:}\n".format(str(self.cellsize)))
                f.write("NODATA_value\t{:}\n".format(str(self.nodata_value)))
                f.write(self.data.strip() + "\n")

            
    def enlargeGrid(self,grid):
        self_bbox = self.getBbox()
        bbox = grid.getBbox()
        
        if (bbox["ymin"] > self_bbox["ymin"] or bbox["ymax"] < self_bbox["ymax"]
            or bbox["xmin"] > self_bbox["xmin"] or bbox["xmax"] < self_bbox["xmax"]):
            raise TypeError("Given grid is to small !!")
            
        top    = int(ceil(abs(self_bbox["ymax"] - bbox["ymax"])/self.cellsize))
        left   = int(ceil(abs(self_bbox["xmin"] - bbox["xmin"])/self.cellsize))
        bottom = int(ceil(abs(self_bbox["ymin"] - bbox["ymin"])/self.cellsize))
        right  = int(ceil(abs(self_bbox["xmax"] - bbox["xmax"])/self.cellsize))

        self.padGrid(top,left,bottom,right)

        
    def padGrid(self=0,top=0,left=0,bottom=0,right=0):

        self.nrows += top + bottom
        self.ncols += left + right        
        self.yllcorner -= bottom*self.cellsize
        self.xllcorner -= left*self.cellsize

        if hasattr(self, 'ncarr'):
            from numpy import zeros
            # initialize 3d field
            self.data = zeros((self.ncarr.shape[0], self.nrows, self.ncols)) + self._nodata_value
            # paste 3d field
            print('***CAUTION: grid cell at (0,0) index is assumed to be in the North-West')
            self.data[:, top: top + self.ncarr.shape[1], left: left + self.ncarr.shape[2]] = self.ncarr
        else:
        
            empty_row = " ".join([str(self.nodata_value),]*self.ncols)
            left_pad = " ".join([str(self.nodata_value),]*left)
            right_pad = " ".join([str(self.nodata_value),]*right)
    
            data = ["{0} {1} {2}".format(left_pad,row,right_pad)
                    for row in self.data.split("\n")]

            self.data = "\n".join([empty_row,]*top + data + [empty_row,]*bottom)

                
    def snapGrid(self,grid):
        delta_y = (grid.yllcorner - self.yllcorner)/float(self.cellsize)
        delta_x = (grid.xllcorner - self.xllcorner)/float(self.cellsize)
        y_offset = delta_y - floor(delta_y)
        x_offset = delta_x - floor(delta_x)
        if y_offset > .5: y_offset -= 1
        if x_offset > .5: x_offset -= 1
        self.yllcorner += self.cellsize * y_offset
        self.xllcorner += self.cellsize * x_offset


def usage(prog_name):
    return "\n".join(
        ["usage for ASCII files:",
         "python {:} grid_infile header_or_gridfile grid_outfile\n"\
         .format(prog_name),
         "Processes 'grid_infile' to match 'header_or_gridfile'.",
         "Output will be written to grid_outfile.",
         "=============================================================================",
         "usage for netCDF files:",
         "python {:} netCDF_infile header_infile header_or_gridfile grid_outfile\n"\
         .format(prog_name),
         "Processes fields in 'netCDF_infile' with header in 'header_infile' to match 'header_or_gridfile'.",
         "Output will be written to grid_outfile."])


if __name__== "__main__":

    if (len(sys.argv) < 4) or \
       (len(sys.argv) > 5) or \
        not all([os.path.isfile(a) for a in sys.argv[1:-1]]):
        print "Invalid arguments !\n"
        print usage(sys.argv[0])
        sys.exit(2)

    # initialize ncfile
    ncfile = None
    if len(sys.argv) == 5:
        ncfile = sys.argv.pop(1)
    
    source_grid = AsciiGrid(sys.argv[1], ncfile=ncfile)
    target_grid = AsciiGrid(sys.argv[2])

    if target_grid.cellsize%source_grid.cellsize != 0:
        print "\n".join(
            ["The cellsizes of 'grid_infile' and 'header_or_gridfile'",
             "are not divisable. If you are sure you gave the right",
             "arguments in the right order, your data processing",
             "for mHM was not succesfull!"
         ])
        sys.exit(2)
        
    source_grid.snapGrid(target_grid)
    source_grid.enlargeGrid(target_grid)
    source_grid.write(sys.argv[3])
