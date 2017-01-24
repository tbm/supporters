#!/usr/bin/env python3

from django.db import models

class Payment(models.Model):
    date = models.DateField()
    entity = models.TextField()
    payee = models.TextField()
    program = models.TextField()
    amount = models.TextField()
