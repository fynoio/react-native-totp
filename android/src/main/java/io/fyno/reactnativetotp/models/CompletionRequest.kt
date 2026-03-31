package io.fyno.reactnativetotp.models

import com.google.gson.annotations.SerializedName

data class CompletionRequest(
    @SerializedName("tenent_id") val tenantId: String,
    @SerializedName("enrolment_id") val enrolmentId: String,
    @SerializedName("key_id") val keyId: String,
    @SerializedName("otp") val otp: String,
    @SerializedName("device_uuid") val deviceUuid: String,
    @SerializedName("user_id") val userId: String,
)
