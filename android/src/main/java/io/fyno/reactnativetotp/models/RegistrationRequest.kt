package io.fyno.reactnativetotp.models

import com.google.gson.annotations.SerializedName
data class RegistrationRequest(
    @SerializedName("tenent_id") val tenantId: String,
    @SerializedName("user_id") val userId: String
)
