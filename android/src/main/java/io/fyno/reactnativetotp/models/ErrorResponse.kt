package io.fyno.reactnativetotp.models

import com.google.gson.annotations.SerializedName

data class ErrorResponse(
    @SerializedName("error") val error: String,
    @SerializedName("message") val message: String
)
