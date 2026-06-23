#!/bin/bash

sudo growpart /dev/vda 1

sudo resize2fs /dev/vda1

