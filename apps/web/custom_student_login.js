"use strict";

if (
  typeof apiRequest !== "function" ||
  typeof teacherPortalActiveGroup !== "function" ||
  typeof teacherPortalSetError !== "function" ||
  typeof teacherPortalHandleError !== "function" ||
  typeof teacherPortalShowCredentials !== "function" ||
  typeof teacherPortalRefreshGroupData !== "function"
) {
  throw new Error("Custom student login UI requires the teacher dashboard to load first.");
}
if (!(teacherPortalCreateStudentForm instanceof HTMLFormElement)) {
  throw new Error("Teacher create-student form was not found.");
}
if (!(teacherPortalCreateStudentError instanceof HTMLElement)) {
  throw new Error("Teacher create-student error element was not found.");
}
if (document.getElementById("teacher-student-login-id") !== null) {
  throw new Error("Teacher student login ID input already exists.");
}

const customStudentLoginPattern = /^[a-z0-9][a-z0-9-]{2,31}$/;
const customStudentLoginLabel = document.createElement("label");
customStudentLoginLabel.textContent = "生徒ID";

const customStudentLoginInput = document.createElement("input");
customStudentLoginInput.id = "teacher-student-login-id";
customStudentLoginInput.name = "login_id";
customStudentLoginInput.type = "text";
customStudentLoginInput.autocomplete = "off";
customStudentLoginInput.inputMode = "text";
customStudentLoginInput.maxLength = 32;
customStudentLoginInput.pattern = "[a-z0-9][a-z0-9-]{2,31}";
customStudentLoginInput.placeholder = "例: yamada";
customStudentLoginInput.required = true;
customStudentLoginInput.spellcheck = false;
customStudentLoginLabel.append(customStudentLoginInput);

const customStudentLoginNote = teacherPortalCreateStudentForm.querySelector(".teacher-management-note");
if (!(customStudentLoginNote instanceof HTMLElement)) {
  throw new Error("Teacher create-student note was not found.");
}
customStudentLoginNote.textContent = "英小文字・数字・ハイフンで3〜32文字。例: yamada / suzuki";
teacherPortalCreateStudentForm.insertBefore(customStudentLoginLabel, customStudentLoginNote);

teacherPortalCreateStudentForm.addEventListener(
  "submit",
  async (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
    teacherPortalSetError(teacherPortalCreateStudentError, null);

    const loginId = customStudentLoginInput.value;
    if (!customStudentLoginPattern.test(loginId)) {
      teacherPortalSetError(
        teacherPortalCreateStudentError,
        "生徒IDは英小文字・数字・ハイフンのみ、3〜32文字で入力してください。",
      );
      return;
    }

    const group = teacherPortalActiveGroup();
    if (group === null) {
      teacherPortalSetError(teacherPortalCreateStudentError, "生徒を追加するクラスを選んでください。");
      return;
    }

    const button = teacherPortalCreateStudentForm.querySelector("button[type='submit']");
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error("Create student submit button was not found.");
    }

    button.disabled = true;
    try {
      const payload = await apiRequest(`/groups/${group.group_id}/students`, {
        method: "POST",
        authenticated: true,
        body: { login_id: loginId },
      });
      customStudentLoginInput.value = "";
      teacherPortalShowCredentials(payload.login_id, payload.temporary_password);
      await teacherPortalRefreshGroupData();
    } catch (error) {
      teacherPortalHandleError(error, teacherPortalCreateStudentError);
    } finally {
      button.disabled = false;
    }
  },
  true,
);
