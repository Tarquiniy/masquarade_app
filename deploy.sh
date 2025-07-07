#!/bin/bash
flutter build web
netlify deploy --dir=build/web
