package com.ethanteng.helloporch.core

/** Input Porch won't accept. The message is written for the person who typed it, like the iOS `errorDescription`s. */
class ValidationException(message: String) : IllegalArgumentException(message)
