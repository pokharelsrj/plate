package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"pi-webpage/components"
	"pi-webpage/db"
)

func ExercisesPage(w http.ResponseWriter, r *http.Request) {
	renderExercisesPage(w, r, "", "")
}

func ExerciseCreate(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderExercisesPage(w, r, "", "bad form data")
		return
	}
	name := strings.TrimSpace(r.FormValue("name"))
	bodyPart := strings.TrimSpace(r.FormValue("body_part"))
	if name == "" {
		renderExercisesPage(w, r, "", "name required")
		return
	}
	if _, err := db.CreateExercise(name, bodyPart); err != nil {
		renderExercisesPage(w, r, "", "could not save (already exists?): "+err.Error())
		return
	}
	http.Redirect(w, r, "/exercises?ok=created", http.StatusSeeOther)
}

func ExerciseUpdate(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderExercisesPage(w, r, "", "bad form data")
		return
	}
	id, err := strconv.ParseInt(r.FormValue("id"), 10, 64)
	if err != nil {
		renderExercisesPage(w, r, "", "bad id")
		return
	}
	name := strings.TrimSpace(r.FormValue("name"))
	bodyPart := strings.TrimSpace(r.FormValue("body_part"))
	if name == "" {
		renderExercisesPage(w, r, "", "name required")
		return
	}
	if err := db.UpdateExercise(id, name, bodyPart); err != nil {
		renderExercisesPage(w, r, "", "update failed: "+err.Error())
		return
	}
	http.Redirect(w, r, "/exercises?ok=updated", http.StatusSeeOther)
}

func ExerciseDelete(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderExercisesPage(w, r, "", "bad form data")
		return
	}
	id, err := strconv.ParseInt(r.FormValue("id"), 10, 64)
	if err != nil {
		renderExercisesPage(w, r, "", "bad id")
		return
	}
	if err := db.DeleteExercise(id); err != nil {
		renderExercisesPage(w, r, "", err.Error())
		return
	}
	http.Redirect(w, r, "/exercises?ok=deleted", http.StatusSeeOther)
}

func renderExercisesPage(w http.ResponseWriter, r *http.Request, _ string, errMsg string) {
	exercises, _ := db.ListExercises()
	counts, _ := db.CountSetsForExercises()
	bps := bodyParts()
	bpCounts, _ := db.CountExercisesByBodyPart()

	editID, _ := strconv.ParseInt(r.URL.Query().Get("edit"), 10, 64)

	groups := groupExercisesByBodyPart(exercises)

	model := components.ExercisesPageModel{
		BodyParts:    bps,
		BodyPartUses: bpCounts,
		Groups:       groups,
		Counts:       counts,
		EditID:       editID,
		ErrorMsg:     errMsg,
		OkMsg:        r.URL.Query().Get("ok"),
	}
	components.ExercisesPage(model).Render(r.Context(), w)
}

func BodyPartCreate(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderExercisesPage(w, r, "", "bad form data")
		return
	}
	name := strings.ToLower(strings.TrimSpace(r.FormValue("name")))
	if name == "" {
		renderExercisesPage(w, r, "", "tag name required")
		return
	}
	if err := db.CreateBodyPart(name); err != nil {
		renderExercisesPage(w, r, "", "could not add (already exists?): "+err.Error())
		return
	}
	http.Redirect(w, r, "/exercises?ok=tag+added", http.StatusSeeOther)
}

func BodyPartDelete(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderExercisesPage(w, r, "", "bad form data")
		return
	}
	name := strings.TrimSpace(r.FormValue("name"))
	if name == "" {
		renderExercisesPage(w, r, "", "tag name required")
		return
	}
	if err := db.DeleteBodyPart(name); err != nil {
		renderExercisesPage(w, r, "", err.Error())
		return
	}
	http.Redirect(w, r, "/exercises?ok=tag+removed", http.StatusSeeOther)
}
